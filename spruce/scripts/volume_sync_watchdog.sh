#!/bin/sh
# Mirror /tmp/system/set_volume into spruce's stored volume so the in-UI volume
# bar tracks the hardware Volume +/- keys, including while a key is held.
#
# /tmp/system/set_volume is the level command file the TrimUI firmware watches:
# whoever wants the volume changed writes the new level there. Two writers exist
# on the A133P devices, and neither keeps spruce's own .vol (SYSTEM_JSON) current
# while a key is held:
#
#   - the stock firmware (trimui_inputd/hardwareservice). On the Brick it owns
#     the volume keys outright (Brick.cfg sets no EVENT_PATH_VOLUME, so spruce's
#     buttons_watchdog never reads them) and writes the file on every key event,
#     autorepeat included. spruce never read it back, so .vol only moved when
#     spruce itself set the volume.
#   - spruce itself, through set_volume. On the Smart Pro buttons_watchdog does
#     own the keys, but its hold loop steps with SAVE_TO_CONFIG=false and only
#     writes .vol when the key is released.
#
# The UI volume bar reads .vol, so either way holding a volume key moved the
# audio while the bar sat still. This watchdog reacts to writes of the command
# file and mirrors the value into SYSTEM_JSON, the file PyUI's config watcher
# polls to redraw the bar. That is its whole job: the durable copy and ALSA
# belong to whoever wrote the command file, so we deliberately do NOT call
# set_volume here (it would just re-poke the command file and add a redundant
# synchronous flash write). Keeping to a single in-place edit of SYSTEM_JSON is
# what lets the bar chase the level instead of crawling behind it.
#
# Events are delivered by inotifywait so there is no fixed poll delay; if it is
# missing or exits we fall back to interval polling so syncing still works.
#
# It also lifts Silent Mode's hard mute on the first volume-up. That switch is
# Brick hardware, so it never fires elsewhere. Silent Mode mutes the speaker amp
# (/sys/class/speaker/mute) and that mute is otherwise only cleared by flipping
# the switch back. So raising the volume bumped ALSA and the OSD but produced no
# sound. When a non-zero volume arrives while Silent Mode's marker is present we
# clear the mute (and the marker) so volume-up restores audio without touching
# the switch.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
[ -f /mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh ] && . /mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh

SET_VOLUME_DIR=/tmp/system
SET_VOLUME_FILE=/tmp/system/set_volume
SPEAKER_MUTE_FILE=/sys/class/speaker/mute
MUTED_MARKER=/tmp/system/muted
INOTIFYWAIT=/mnt/SDCARD/spruce/bin64/inotifywait
POLL_INTERVAL=0.15     # fallback polling cadence when inotifywait is unavailable

mkdir -p "$SET_VOLUME_DIR" 2>/dev/null

last_seen=""

# Lift Silent Mode's amp mute when the volume is raised above 0. Gated on Silent
# Mode's own marker so we only ever clear the mute Silent Mode set: the Smart Pro
# and Smart Pro S also mute the amp for the first seconds of boot to avoid an
# audio pop, and the startup volume keypresses they simulate must not cut that
# short.
unmute_if_raised() {
    vol="$1"
    [ "$vol" -gt 0 ] 2>/dev/null || return 0
    [ -f "$MUTED_MARKER" ] || return 0
    [ -w "$SPEAKER_MUTE_FILE" ] || return 0
    [ "$(cat "$SPEAKER_MUTE_FILE" 2>/dev/null)" = "1" ] || return 0
    echo 0 > "$SPEAKER_MUTE_FILE"
    rm -f "$MUTED_MARKER"
    log_message "volume_sync_watchdog.sh: volume raised to $vol, cleared Silent Mode mute."
}

read_current() {
    new_vol=$(cat "$SET_VOLUME_FILE" 2>/dev/null)
    case "$new_vol" in
        ''|*[!0-9]*) return 1 ;;   # ignore empty or non-numeric writes
    esac
    echo "$new_vol"
}

# Mirror one observed value into the bar (SYSTEM_JSON), in place, and handle the
# Silent Mode unmute. Cheap enough to run on every key event, even held.
sync_value() {
    new_vol="$1"
    [ -e /tmp/sleep_helper_started ] && return 0

    [ "$new_vol" = "$last_seen" ] && return 0
    last_seen="$new_vol"
    if [ "$new_vol" != "$(get_volume_level)" ]; then
        sed -i "s/\"vol\":[[:space:]]*[0-9]*/\"vol\": $new_vol/" "$SYSTEM_JSON" 2>/dev/null
    fi
    unmute_if_raised "$new_vol"
}

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
            log_message "volume_sync_watchdog.sh: fan level updated to $val"
            ;;
    esac
}

handle_led_on_event() {
    rm -f /tmp/system/led_turn_on /tmp/system/set_led 2>/dev/null
    flag_remove "leds_forced_off"
    echo 25 > /sys/class/led_anim/max_scale 2>/dev/null
    echo 1 > /sys/class/led_anim/enable 2>/dev/null
    echo 1 > /sys/class/led_anim/effect_enable 2>/dev/null
    /usr/trimui/bin/shmvar ledvalue 6 2>/dev/null
    /usr/trimui/bin/shmvar ledswitch 1 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_led 2>/dev/null
    echo 1 > /tmp/trimui_osd/toggle_led/status 2>/dev/null
    hex="$(led_color_hex 2>/dev/null)"
    [ -z "$hex" ] && hex="00FF00"
    rgb_led_trimui lrm12 static "$hex" &
    log_message "volume_sync_watchdog.sh: handled led_turn_on"
}

handle_led_off_event() {
    rm -f /tmp/system/led_turn_off /tmp/system/set_led 2>/dev/null
    flag_remove "leds_forced_off"
    rgb_led_trimui lrm12 static "000000" &
    flag_add "leds_forced_off" --tmp
    echo 0 > /sys/class/led_anim/max_scale 2>/dev/null
    /usr/trimui/bin/shmvar ledswitch 0 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_led 2>/dev/null
    echo 0 > /tmp/trimui_osd/toggle_led/status 2>/dev/null
    log_message "volume_sync_watchdog.sh: handled led_turn_off"
}

handle_wifi_on_event() {
    rm -f /tmp/system/wifi_turn_on /tmp/system/set_wifi 2>/dev/null
    enable_wifi &
    sed -i 's/"wifi":[[:space:]]*[0-9]*/"wifi": 1/' "$SYSTEM_JSON" 2>/dev/null
    /usr/trimui/bin/shmvar wifiswitch 1 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_wifi 2>/dev/null
    echo 1 > /tmp/trimui_osd/toggle_wifi/status 2>/dev/null
    log_message "volume_sync_watchdog.sh: handled wifi_turn_on"
}

handle_wifi_off_event() {
    rm -f /tmp/system/wifi_turn_off /tmp/system/set_wifi 2>/dev/null
    disable_wifi &
    sed -i 's/"wifi":[[:space:]]*[0-9]*/"wifi": 0/' "$SYSTEM_JSON" 2>/dev/null
    /usr/trimui/bin/shmvar wifiswitch 0 2>/dev/null
    mkdir -p /tmp/trimui_osd/toggle_wifi 2>/dev/null
    echo 0 > /tmp/trimui_osd/toggle_wifi/status 2>/dev/null
    log_message "volume_sync_watchdog.sh: handled wifi_turn_off"
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
    log_message "volume_sync_watchdog.sh: handled bluetooth_turn_on"
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
    log_message "volume_sync_watchdog.sh: handled bluetooth_turn_off"
}

run_event_driven() {
    "$INOTIFYWAIT" -m -q -e create -e modify -e close_write -e moved_to -e attrib \
        --format '%f' "$SET_VOLUME_DIR" 2>/dev/null | \
    while read -r fname; do
        case "$fname" in
            "set_volume")
                cur="$(read_current)" || continue
                sync_value "$cur"
                ;;
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
        esac
    done
}

run_polling_fallback() {
    log_message "volume_sync_watchdog.sh: inotifywait unavailable, using polling fallback."
    while true; do
        if [ -f "$SET_VOLUME_FILE" ]; then
            cur="$(read_current)" && sync_value "$cur"
        fi
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
        sleep "$POLL_INTERVAL"
    done
}

log_message "volume_sync_watchdog.sh: Started up."

if [ -x "$INOTIFYWAIT" ]; then
    # If inotifywait ever exits, drop back to polling so syncing never stops.
    run_event_driven
    log_message "volume_sync_watchdog.sh: event loop ended, falling back to polling."
fi
run_polling_fallback
