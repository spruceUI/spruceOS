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
    case "$name" in
        Red)     echo "FF0000" ;;
        Green)   echo "00FF00" ;;
        Blue)    echo "0000FF" ;;
        Yellow)  echo "FFFF00" ;;
        Cyan)    echo "00FFFF" ;;
        Magenta) echo "FF00FF" ;;
        Orange)  echo "FF8800" ;;
        *)       echo "FFFFFF" ;;
    esac
}

rgb_led_trimui() {

    # early out if disabled
	disable="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
	[ "$disable" = "True" ] && return 0

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
	flag_check "leds_forced_off" && return 0

    # get and set peak rgb brightness
    max_scale="$(get_config_value '.menuOptions."RGB LED Settings".LEDmaxScale.selected' "False")"
    echo "$max_scale" > "/sys/class/led_anim/max_scale"

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

    # translate 1 → f1 and 2 → f2
    new_zones=""
    for z in $zones; do
        case "$z" in
            1) new_zones="$new_zones f1" ;;
            2) new_zones="$new_zones f2" ;;
            *) new_zones="$new_zones $z" ;;
        esac
    done
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

    # get color, duration, and cycles literally from args 3,4,5, with fallbacks if missing
    color=${3:-"FFFFFF"}
    duration=${4:-1000}
    cycles=${5:-1}

    # do the things
   	echo 1 > /sys/class/led_anim/effect_enable 2>/dev/null
    for zone in $zones; do
        [ -w "/sys/class/led_anim/effect_rgb_hex_$zone" ] && echo "$color" > "/sys/class/led_anim/effect_rgb_hex_$zone"
        [ -w "/sys/class/led_anim/effect_cycles_$zone" ] && echo "$cycles" > "/sys/class/led_anim/effect_cycles_$zone"
        [ -w "/sys/class/led_anim/effect_duration_$zone" ] && echo "$duration" > "/sys/class/led_anim/effect_duration_$zone"
        [ -w "/sys/class/led_anim/effect_$zone" ] && echo "$effect" > "/sys/class/led_anim/effect_$zone"
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
    /mnt/SDCARD/spruce/scripts/volume_sync_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n volume_sync_watchdog.sh &

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

        LD_LIBRARY_PATH=/usr/trimui/lib "./$blob" &
        log_message "Started $blob"
        sleep 0.05
    done
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
