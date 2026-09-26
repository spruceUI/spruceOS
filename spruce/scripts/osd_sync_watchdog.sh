#!/bin/sh
# osd_sync_watchdog.sh
# Dedicated watchdog for TrimUI OSD events (/tmp/system/)
# to keep hardware state, system.json, shmvar, and OSD status tiles synchronized.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
[ -f /mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh ] && . /mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh

rgb_led() {
    rgb_led_trimui "$@"
}

SET_SYSTEM_DIR=/tmp/system
INOTIFYWAIT=/mnt/SDCARD/spruce/bin64/inotifywait
POLL_INTERVAL=0.25

mkdir -p "$SET_SYSTEM_DIR" 2>/dev/null

handle_fan_event() {
    val=""
    if [ -f /tmp/system/set_fanlevel ]; then
        val="$(cat /tmp/system/set_fanlevel 2>/dev/null)"
        rm -f /tmp/system/set_fanlevel 2>/dev/null
    elif [ -f /tmp/system/set_fan ]; then
        val="$(cat /tmp/system/set_fan 2>/dev/null)"
        rm -f /tmp/system/set_fan 2>/dev/null
    fi
    if [ -z "$val" ]; then
        if [ -f /tmp/trimui_osd/stepper_fanlevel/status ]; then
            val="$(cat /tmp/trimui_osd/stepper_fanlevel/status 2>/dev/null)"
        elif [ -f /tmp/trimui_osd/stepper_fan/status ]; then
            val="$(cat /tmp/trimui_osd/stepper_fan/status 2>/dev/null)"
        elif [ -x /usr/trimui/bin/shmvar ]; then
            val="$(/usr/trimui/bin/shmvar fanlevel 2>/dev/null)"
        fi
    fi
    case "$val" in
        -1|0|1|2|3|4|5|6)
            apply_fan_level "$val"
            save_fan_level "$val"
            log_message "osd_sync_watchdog.sh: fan level updated to $val"
            ;;
    esac
}

handle_led_on_event() {
    rm -f /tmp/system/led_turn_on /tmp/system/set_led 2>/dev/null
    flag_remove "leds_forced_off"
    hex="$(led_color_hex)"
    echo 25 > /sys/class/led_anim/max_scale 2>/dev/null
    echo 1 > /sys/class/led_anim/enable 2>/dev/null
    rgb_led_trimui lrm12 static "$hex" &
    /usr/trimui/bin/shmvar ledswitch 1 2>/dev/null
    /usr/trimui/bin/shmvar ledvalue 6 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_led 2>/dev/null
    echo 1 > /tmp/trimui_osd/toggle_led/status 2>/dev/null
    log_message "osd_sync_watchdog.sh: handled led_turn_on"
}

handle_led_off_event() {
    rm -f /tmp/system/led_turn_off /tmp/system/set_led 2>/dev/null
    flag_add "leds_forced_off" --tmp
    echo 0 > /sys/class/led_anim/max_scale 2>/dev/null
    rgb_led_trimui lrm12 static "000000" &
    /usr/trimui/bin/shmvar ledswitch 0 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_led 2>/dev/null
    echo 0 > /tmp/trimui_osd/toggle_led/status 2>/dev/null
    log_message "osd_sync_watchdog.sh: handled led_turn_off"
}

handle_wifi_on_event() {
    rm -f /tmp/system/wifi_turn_on /tmp/system/set_wifi 2>/dev/null
    enable_wifi &
    sed -i 's/"wifi":[[:space:]]*[0-9]*/"wifi": 1/' "$SYSTEM_JSON" 2>/dev/null
    /usr/trimui/bin/shmvar wifiswitch 1 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_wifi 2>/dev/null
    echo 1 > /tmp/trimui_osd/toggle_wifi/status 2>/dev/null
    log_message "osd_sync_watchdog.sh: handled wifi_turn_on"
}

handle_wifi_off_event() {
    rm -f /tmp/system/wifi_turn_off /tmp/system/set_wifi 2>/dev/null
    disable_wifi &
    sed -i 's/"wifi":[[:space:]]*[0-9]*/"wifi": 0/' "$SYSTEM_JSON" 2>/dev/null
    /usr/trimui/bin/shmvar wifiswitch 0 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_wifi 2>/dev/null
    echo 0 > /tmp/trimui_osd/toggle_wifi/status 2>/dev/null
    log_message "osd_sync_watchdog.sh: handled wifi_turn_off"
}

handle_bt_on_event() {
    rm -f /tmp/system/bluetooth_turn_on /tmp/system/set_bt /tmp/system/set_bluetooth 2>/dev/null
    (
        /etc/bluetooth/bt_init.sh start 2>/dev/null
        if [ -z "$(pgrep hciattach)" ]; then
            hciattach -n ttyAS1 aic 2>/dev/null &
        fi
        /etc/bluetooth/bluetoothd start 2>/dev/null
    ) &
    sed -i 's/"bluetooth":[[:space:]]*[0-9]*/"bluetooth": 1/' "$SYSTEM_JSON" 2>/dev/null
    /usr/trimui/bin/shmvar btswitch 1 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_bt 2>/dev/null
    echo 1 > /tmp/trimui_osd/toggle_bt/status 2>/dev/null
    log_message "osd_sync_watchdog.sh: handled bluetooth_turn_on"
}

handle_bt_off_event() {
    rm -f /tmp/system/bluetooth_turn_off /tmp/system/set_bt /tmp/system/set_bluetooth 2>/dev/null
    killall -15 bluetoothd 2>/dev/null
    sleep 0.1
    killall -9 bluetoothd 2>/dev/null
    killall -9 hciattach 2>/dev/null
    sed -i 's/"bluetooth":[[:space:]]*[0-9]*/"bluetooth": 0/' "$SYSTEM_JSON" 2>/dev/null
    /usr/trimui/bin/shmvar btswitch 0 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_bt 2>/dev/null
    echo 0 > /tmp/trimui_osd/toggle_bt/status 2>/dev/null
    log_message "osd_sync_watchdog.sh: handled bluetooth_turn_off"
}

handle_rumble_on_event() {
    rm -f /tmp/system/rumble_turn_on /tmp/system/set_rumble 2>/dev/null
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"
    case "$intensity" in
        "Weak")   scale=50 ;;
        "Strong") scale=100 ;;
        *)        scale=75 ;;
    esac
    echo "$scale" > /sys/class/motor/max_scale 2>/dev/null
    /usr/trimui/bin/shmvar rumbleswitch 1 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_rumble 2>/dev/null
    echo 1 > /tmp/trimui_osd/toggle_rumble/status 2>/dev/null
    # Tactile confirmation pulse
    (
        echo -n 65535 > /sys/class/motor/level 2>/dev/null
        usleep 90000 2>/dev/null || sleep 0.1
        echo -n 0 > /sys/class/motor/level 2>/dev/null
    ) &
    log_message "osd_sync_watchdog.sh: handled rumble_turn_on"
}

handle_rumble_off_event() {
    rm -f /tmp/system/rumble_turn_off /tmp/system/set_rumble 2>/dev/null
    echo 0 > /sys/class/motor/max_scale 2>/dev/null
    echo -n 0 > /sys/class/motor/level 2>/dev/null
    /usr/trimui/bin/shmvar rumbleswitch 0 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_rumble 2>/dev/null
    echo 0 > /tmp/trimui_osd/toggle_rumble/status 2>/dev/null
    log_message "osd_sync_watchdog.sh: handled rumble_turn_off"
}

run_event_driven() {
    "$INOTIFYWAIT" -m -q -e create -e modify -e close_write -e moved_to -e attrib \
        --format '%f' "$SET_SYSTEM_DIR" 2>/dev/null | \
    while read -r fname; do
        case "$fname" in
            "set_fanlevel"|"set_fan")
                handle_fan_event
                ;;
            "led_turn_on")
                handle_led_on_event
                ;;
            "led_turn_off")
                handle_led_off_event
                ;;
            "set_led")
                val="$(cat /tmp/system/set_led 2>/dev/null)"
                rm -f /tmp/system/set_led 2>/dev/null
                if [ "$val" = "0" ]; then
                    handle_led_off_event
                else
                    handle_led_on_event
                fi
                ;;
            "wifi_turn_on")
                handle_wifi_on_event
                ;;
            "wifi_turn_off")
                handle_wifi_off_event
                ;;
            "set_wifi")
                val="$(cat /tmp/system/set_wifi 2>/dev/null)"
                rm -f /tmp/system/set_wifi 2>/dev/null
                if [ "$val" = "0" ]; then
                    handle_wifi_off_event
                else
                    handle_wifi_on_event
                fi
                ;;
            "bluetooth_turn_on")
                handle_bt_on_event
                ;;
            "bluetooth_turn_off")
                handle_bt_off_event
                ;;
            "set_bt"|"set_bluetooth")
                val="$(cat "/tmp/system/$fname" 2>/dev/null)"
                rm -f "/tmp/system/$fname" 2>/dev/null
                if [ "$val" = "0" ]; then
                    handle_bt_off_event
                else
                    handle_bt_on_event
                fi
                ;;
            "rumble_turn_on")
                handle_rumble_on_event
                ;;
            "rumble_turn_off")
                handle_rumble_off_event
                ;;
            "set_rumble")
                val="$(cat /tmp/system/set_rumble 2>/dev/null)"
                rm -f /tmp/system/set_rumble 2>/dev/null
                if [ "$val" = "0" ]; then
                    handle_rumble_off_event
                else
                    handle_rumble_on_event
                fi
                ;;
        esac
    done
}

run_polling_fallback() {
    log_message "osd_sync_watchdog.sh: inotifywait unavailable, using polling fallback."
    while true; do
        if [ -f /tmp/system/set_fanlevel ] || [ -f /tmp/system/set_fan ]; then
            handle_fan_event
        fi
        if [ -f /tmp/system/led_turn_on ]; then
            handle_led_on_event
        fi
        if [ -f /tmp/system/led_turn_off ]; then
            handle_led_off_event
        fi
        if [ -f /tmp/system/set_led ]; then
            val="$(cat /tmp/system/set_led 2>/dev/null)"
            rm -f /tmp/system/set_led 2>/dev/null
            if [ "$val" = "0" ]; then handle_led_off_event; else handle_led_on_event; fi
        fi
        if [ -f /tmp/system/wifi_turn_on ]; then
            handle_wifi_on_event
        fi
        if [ -f /tmp/system/wifi_turn_off ]; then
            handle_wifi_off_event
        fi
        if [ -f /tmp/system/set_wifi ]; then
            val="$(cat /tmp/system/set_wifi 2>/dev/null)"
            rm -f /tmp/system/set_wifi 2>/dev/null
            if [ "$val" = "0" ]; then handle_wifi_off_event; else handle_wifi_on_event; fi
        fi
        if [ -f /tmp/system/bluetooth_turn_on ]; then
            handle_bt_on_event
        fi
        if [ -f /tmp/system/bluetooth_turn_off ]; then
            handle_bt_off_event
        fi
        if [ -f /tmp/system/rumble_turn_on ]; then
            handle_rumble_on_event
        fi
        if [ -f /tmp/system/rumble_turn_off ]; then
            handle_rumble_off_event
        fi
        sleep "$POLL_INTERVAL"
    done
}

log_message "osd_sync_watchdog.sh: Started up."

if [ -x "$INOTIFYWAIT" ]; then
    run_event_driven
    log_message "osd_sync_watchdog.sh: event loop ended, falling back to polling."
fi
run_polling_fallback
