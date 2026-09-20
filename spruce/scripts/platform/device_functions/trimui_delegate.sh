#!/bin/sh

# Methods that seem common to TrimUI but probably aren't as more devices
# From them get released. But we can more easily rename/call them from here
# Without having to worry about the 'inheritance' change we are mimicing
# via sh file order importing

# ---------------------------------------------------------------------------
# rgb_led <zones> <effect> [color] [duration_ms] [cycles] [A30/Flip led trigger]
#
# Controls RGB LEDs on TrimUI Brick / Smart Pro.
#
# PARAMETERS:
#   <zones>        A string containing any combination of: l r m 1 2
#                  (order does not matter)
#                  Zones resolve to:
#                     l  → left LED
#                     r  → right LED
#                     m  → middle LED
#                     1  → front LED f1
#                     2  → front LED f2
#                  Example: "lrm12", "m1", "r2", "l"
#
#   <effect>       One of the following keywords or numeric equivalents:
#                     0 | off | disable      → off
#                     1 | linear | rise      → linear rise
#                     2 | breath*            → breathing pattern
#                     3 | sniff              → "sniff" animation
#                     4 | static | on        → solid color
#                     5 | blink*1            → blink pattern 1
#                     6 | blink*2            → blink pattern 2
#                     7 | blink*3            → blink pattern 3
#
#   [color]        Hex RGB color (default: "FFFFFF")
#
#   [duration_ms]  Animation duration in milliseconds (default: 1000)
#
#   [cycles]       Number of animation cycles (default: 1)
#
#   [led trigger]  none battery-charging-or-full battery-charging battery-full 
#                  battery-charging-blink-full-solid usb-online ac-online 
#                  timer heartbeat gpio default-on mmc1 mmc0
#
#
# EXAMPLES:
#   rgb_led lrm breathe FF8800 2000 3 heartbeat
#   rgb_led m2 blink1 00FFAA
#   rgb_led 12 static
#   rgb_led r off
# ---------------------------------------------------------------------------

# Map the RGB LED Settings "defaultLEDcolor" name to a hex string.
# Shared by the Smart Pro S Home "Toggle LED" action and scene-rgb-led.sh so the
# colour table lives in one place. Pass an explicit name to override the config.
led_color_hex() {
    name="${1:-$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDcolor.selected' "White")}"
    if command -v map_color_name_to_hex >/dev/null 2>&1; then
        map_color_name_to_hex "$name"
    else
        case "$name" in
            "Red")          echo "FF0000" ;;
            "Pink")         echo "FF3333" ;;
            "Fuchsia")      echo "FF0022" ;;
            "Purple")       echo "FF00FF" ;;
            "Dark Purple")  echo "2200CC" ;;
            "Blue")         echo "0000FF" ;;
            "Cyan")         echo "00FFFF" ;;
            "Teal")         echo "00FF22" ;;
            "Green")        echo "00FF00" ;;
            "Yellow")       echo "FFFF00" ;;
            "Orange")       echo "FF1100" ;;
            *)              echo "FFFFFF" ;;
        esac
    fi
}

rgb_led_trimui() {

    # early out if disabled
	disable="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
	[ "$disable" = "True" ] && return 0

	# get color, duration, and cycles literally from args 3,4,5, with fallbacks if missing
	color=${3:-"FFFFFF"}
	duration=${4:-1000}
	cycles=${5:-1}

	# ...and if the switch or an Fn key has turned the LEDs off. That action
	# writes black directly, which lasts only until something else writes a
	# colour - and principal.sh calls set_rgb_in_menu on EVERY return to the
	# menu, while led_effect re-colours them on every game launch. Both come
	# through here, so without this the LEDs came back on the moment you left a
	# game and stayed on until the switch was cycled.
	#
	# Deliberately not the disableLEDs setting itself: that is the user's own
	# "off in all contexts" preference, and a physical switch should not
	# silently rewrite it. /tmp, so it clears on reboot - which matches the
	# action, since scene.sh only runs on an actual flip and nothing re-applies
	# the switch position at boot.
	if flag_check "leds_forced_off" && [ "$color" != "000000" ] && [ "$2" != "0" ] && [ "$2" != "off" ]; then
		return 0
	fi

    # get and set peak rgb brightness
    max_scale="$(get_config_value '.menuOptions."RGB LED Settings".LEDmaxScale.selected' "25")"
    if [ -z "$max_scale" ] || [ "$max_scale" = "False" ]; then
        max_scale="25"
    fi
    echo "$max_scale" > "/sys/class/led_anim/max_scale" 2>/dev/null

    # parse led zones to affect from first argument
    if [ -n "$1" ]; then
        zones=""
        for z in l r m 1 2; do
            case "$1" in
                *"$z"*) zones="$zones $z";;
            esac
        done
    else
        zones="l r m 1 2"
    fi

    # translate 1 → f1 and 2 → f2; also add lr when l or r are targeted (Smart Pro / Smart Pro S joystick ring)
    new_zones=""
    has_lr=0
    for z in $zones; do
        case "$z" in
            1) new_zones="$new_zones f1" ;;
            2) new_zones="$new_zones f2" ;;
            l|r)
                new_zones="$new_zones $z"
                has_lr=1
                ;;
            *) new_zones="$new_zones $z" ;;
        esac
    done
    [ $has_lr -eq 1 ] && new_zones="$new_zones lr"
    zones="$new_zones"

    # parse effect to use from second argument
    case "$2" in
        0|off|disable) effect=0 ;;
        1|linear|rise) effect=1 ;;
        2|breath*) effect=2 ;;
        3|sniff) effect=3 ;;
        4|static|on) effect=4 ;;
        5|blink*1) effect=5 ;;
        6|blink*2) effect=6 ;;
        7|blink*3) effect=7 ;;
        *) effect=4 ;;
    esac

    # do the things
    chmod -R 777 /sys/class/led_anim 2>/dev/null
    echo 1 > /sys/class/led_anim/enable 2>/dev/null
   	echo 1 > /sys/class/led_anim/effect_enable 2>/dev/null
    for zone in $zones; do
        if [ -w "/sys/class/led_anim/effect_rgb_hex_$zone" ]; then
            printf "%s " "$color" > "/sys/class/led_anim/effect_rgb_hex_$zone" 2>/dev/null || echo "$color" > "/sys/class/led_anim/effect_rgb_hex_$zone" 2>/dev/null
        fi
        [ -w "/sys/class/led_anim/effect_cycles_$zone" ] && echo "$cycles" > "/sys/class/led_anim/effect_cycles_$zone" 2>/dev/null
        [ -w "/sys/class/led_anim/effect_duration_$zone" ] && echo "$duration" > "/sys/class/led_anim/effect_duration_$zone" 2>/dev/null
        if [ -w "/sys/class/led_anim/effect_$zone" ]; then
            echo 0 > "/sys/class/led_anim/effect_$zone" 2>/dev/null
            echo "$effect" > "/sys/class/led_anim/effect_$zone" 2>/dev/null
        fi
    done
}

enable_or_disable_rgb_trimui() {
    enable_file="/sys/class/led_anim/enable"
    disable_rgb="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
    if [ "$disable_rgb" = "True" ]; then
        chmod 777 "$enable_file" 2>/dev/null
        echo 0 > "$enable_file" 2>/dev/null
        chmod 000 "$enable_file" 2>/dev/null
    else
        chmod 777 "$enable_file" 2>/dev/null
        echo 1 > "$enable_file" 2>/dev/null
        # don't lock them back afterwards
    fi

}

setup_for_retroarch() {

	export CORE_DIR="$RA_DIR/.retroarch/cores64"

	if [ "$CORE" = "uae4arm" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
	elif [ "$CORE" = "easyrpg" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR/lib-trimui:$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
	elif [ "$CORE" = "genesis_plus_gx" ] && [ "$DISPLAY_ASPECT_RATIO" = "16:9" ]; then
		use_gpgx_wide="$(get_config_value '.menuOptions."Emulator Settings".genesisPlusGXWide.selected' "False")"
		[ "$use_gpgx_wide" = "True" ] && CORE="genesis_plus_gx_wide"
	fi

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

    echo "$RA_BIN"

}



compare_current_version_to_version_trimui() {
    target_version="$1"
    current_version="$(cat /etc/version 2>/dev/null)"

    [ -z "$target_version" ] && target_version="1.0.0"
    [ -z "$current_version" ] && current_version="1.0.0"

    # Split versions into components
    C_1=$(echo "$current_version" | cut -d. -f1)
    C_2=$(echo "$current_version" | cut -d. -f2)
    C_3=$(echo "$current_version" | cut -d. -f3)
    C_2=${C_2:-0}
    C_3=${C_3:-0}

    T_1=$(echo "$target_version" | cut -d. -f1)
    T_2=$(echo "$target_version" | cut -d. -f2)
    T_3=$(echo "$target_version" | cut -d. -f3)
    T_2=${T_2:-0}
    T_3=${T_3:-0}

    i=1
    while [ $i -le 3 ]; do
        eval C=\$C_$i
        eval T=\$T_$i

        if [ "$C" -gt "$T" ]; then
            echo "newer"
            return 0
        elif [ "$C" -lt "$T" ]; then
            echo "older"
            return 2
        fi
        i=$((i + 1))
    done

    echo "same"
    return 1
}

# Should the above be merged into here?
check_if_fw_needs_update_trimui() {
    current_fw_is="$(compare_current_version_to_version_trimui "$TARGET_FW_VERSION")"
    [ "$current_fw_is" != "older" ] && echo "false" || echo "true"
}

# Common startup watchdogs for every TrimUI device, plus the volume sync one.
# Devices with extra watchdogs (the Brick and its Fn keys) override
# launch_startup_watchdogs and call this first.
launch_trimui_startup_watchdogs() {
    launch_common_startup_watchdogs_v2

    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}

    # Keep spruce's stored volume in sync with whoever last wrote
    # /tmp/system/set_volume (the stock firmware on the Brick, spruce's own hold
    # loop on the Smart Pro and Smart Pro S) so the in-UI volume bar tracks the
    # hardware Volume +/- keys, including while a key is held.
    stop_running_watchdog /mnt/SDCARD/spruce/scripts/volume_sync_watchdog.sh
    /mnt/SDCARD/spruce/scripts/volume_sync_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n volume_sync_watchdog.sh &

    # USB WiFi dongle hot-plug (utils/usb_wifi_dongle.sh). Only the devices
    # whose cfg points at dongle modules run it; the script itself exits at
    # once without WIFI_USB_MODULES_DIR, but there is no point starting it.
    stop_running_watchdog /mnt/SDCARD/spruce/scripts/usb_wifi_watchdog.sh
    if [ -n "$WIFI_USB_MODULES_DIR" ]; then
        /mnt/SDCARD/spruce/scripts/usb_wifi_watchdog.sh &
        pin_cpu "$SYSTEM_CPU" -n usb_wifi_watchdog.sh &
    fi

    /mnt/SDCARD/spruce/scripts/enable_zram.sh &
}

launch_startup_watchdogs() {
    launch_trimui_startup_watchdogs
}

run_trimui_blobs() {
    blobs="$1"

    cd /usr/trimui/bin || return 1
    mkdir -p /tmp/trimui_inputd

    for blob in $blobs; do
        if [ ! -x "./$blob" ]; then
            log_message "$blob not present on this device."
            continue
        fi

        if ps | grep "[/]$blob" >/dev/null 2>&1; then
            log_message "$blob already running, skipping."
            continue
        fi

        bin="./$blob"
        if [ "$blob" = "trimui_inputd" ] && [ -x "$TRIMUI_INPUTD_PATCHED" ]; then
            bin="$TRIMUI_INPUTD_PATCHED"
        fi

        LD_LIBRARY_PATH=/usr/trimui/lib "$bin" &
        log_message "Started $bin"
        sleep 0.05
    done
}

# For stick calibration on inputd builds without cal_update. The restart recreates
# the pad device, so the getevent watchdogs have to reopen it too.
restart_trimui_inputd() {
    log_message "Restarting trimui_inputd and the button watchdogs"
    killall -9 trimui_inputd
    sleep 0.3
    run_trimui_blobs "trimui_inputd"
    sleep 1

    for wd in /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh; do
        stop_running_watchdog "$wd"
    done
    sleep 1
    /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh </dev/null >/dev/null 2>&1 &
    /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh </dev/null >/dev/null 2>&1 &

    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}
    pin_cpu "$SYSTEM_CPU" -n homebutton_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n buttons_watchdog.sh &
}


run_trimui_osdd() {
    if [ -x "/usr/trimui/osd/trimui_osdd" ]; then
        cd /usr/trimui/osd || return 1
        LD_LIBRARY_PATH=/usr/trimui/lib ./trimui_osdd &
        log_message "Attempted to start trimui_osdd"
    else
        log_message "trimui_osdd not found. Skipping."
    fi

    {
        sleep 2 # ensure OSDD fully initializes before setting hotkey
        echo -n $OSD_HOTKEY > /tmp/trimui_osd/hotkeyshow   # tells keymon to pull up OSD
    } &
}

current_backlight() {
    jq -r '.backlight' "$SYSTEM_JSON"
}

brightness_down() {
    local backlight
    backlight=$(current_backlight)
    set_backlight $((backlight - 1))
}

brightness_up() {
    local backlight
    backlight=$(current_backlight)
    set_backlight $((backlight + 1))
}

apply_fan_level() {
    level="$1"
    case "$level" in
        -1|"auto"|"Auto")
            # Auto mode: start Spruce's thermal manager
            if [ -x /mnt/SDCARD/spruce/smartpros/bin/update-thermal-watchdog-to-setting ]; then
                /mnt/SDCARD/spruce/smartpros/bin/update-thermal-watchdog-to-setting &
            fi
            echo -1 > /sys/devices/platform/soc@3000000/soc@3000000:pwm_fan/hwmon/hwmon0/user_max_state 2>/dev/null
            log_message "apply_fan_level: Fan set to Auto (-1)"
            ;;
        0)
            # Fan Off
            /mnt/SDCARD/spruce/smartpros/bin/pkill -9 -f /mnt/SDCARD/spruce/smartpros/bin/thermal-watchdog 2>/dev/null || killall -9 thermal-watchdog 2>/dev/null
            /mnt/SDCARD/spruce/smartpros/bin/pkill -9 -f "adaptive_fan.py" 2>/dev/null
            killall -9 thermal-watchdog 2>/dev/null
            for pid in $(ps 2>/dev/null | grep -E "[a]daptive_fan|[t]hermal-watchdog" | awk '{print $1}'); do
                [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
            done
            echo 0 > /sys/class/thermal/cooling_device0/cur_state 2>/dev/null
            echo 0 > /sys/devices/platform/soc@3000000/soc@3000000:pwm_fan/hwmon/hwmon0/user_max_state 2>/dev/null
            log_message "apply_fan_level: Fan set to Off (0)"
            ;;
        1|2|3|4|5|6)
            # Manual Fan Level 1..6
            /mnt/SDCARD/spruce/smartpros/bin/pkill -9 -f /mnt/SDCARD/spruce/smartpros/bin/thermal-watchdog 2>/dev/null || killall -9 thermal-watchdog 2>/dev/null
            /mnt/SDCARD/spruce/smartpros/bin/pkill -9 -f "adaptive_fan.py" 2>/dev/null
            killall -9 thermal-watchdog 2>/dev/null
            for pid in $(ps 2>/dev/null | grep -E "[a]daptive_fan|[t]hermal-watchdog" | awk '{print $1}'); do
                [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
            done
            case "$level" in
                1) speed=20 ;;
                2) speed=22 ;;
                3) speed=24 ;;
                4) speed=26 ;;
                5) speed=28 ;;
                6) speed=31 ;;
                *) speed=24 ;;
            esac
            # Unlock user_max_state FIRST, otherwise kernel pwm-fan driver rejects cur_state > user_max_state with -EINVAL
            echo -1 > /sys/devices/platform/soc@3000000/soc@3000000:pwm_fan/hwmon/hwmon0/user_max_state 2>/dev/null
            echo "$speed" > /sys/class/thermal/cooling_device0/cur_state 2>/dev/null
            echo "$speed" > /sys/devices/platform/soc@3000000/soc@3000000:pwm_fan/hwmon/hwmon0/user_max_state 2>/dev/null
            log_message "apply_fan_level: Fan set to Manual Level $level (speed $speed)"
            ;;
    esac
}

save_fan_level() {
    level="$1"
    [ -z "$level" ] && return 0
    if [ -f "$SYSTEM_JSON" ]; then
        if grep -q '"fanlevel"' "$SYSTEM_JSON"; then
            sed -i "s/\"fanlevel\":[[:space:]]*-*[0-9]*/\"fanlevel\": $level/" "$SYSTEM_JSON" 2>/dev/null
        else
            tmp="${SYSTEM_JSON}.tmp.$$"
            sed "s/^[[:space:]]*\}/    ,\"fanlevel\": $level\n}/" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON" || rm -f "$tmp"
        fi
    fi
    if [ -f /mnt/UDISK/system.json ]; then
        if grep -q '"fanlevel"' /mnt/UDISK/system.json; then
            sed -i "s/\"fanlevel\":[[:space:]]*-*[0-9]*/\"fanlevel\": $level/" /mnt/UDISK/system.json 2>/dev/null
        else
            tmp="/mnt/UDISK/system.json.tmp.$$"
            sed "s/^[[:space:]]*\}/    ,\"fanlevel\": $level\n}/" /mnt/UDISK/system.json > "$tmp" && mv "$tmp" /mnt/UDISK/system.json || rm -f "$tmp"
        fi
    fi
}

