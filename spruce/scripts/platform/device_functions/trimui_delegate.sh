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

rgb_led_trimui() {

    # early out if disabled
	disable="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
	[ "$disable" = "True" ] && return 0

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

setup_for_retroarch_and_get_bin_location_trimui(){
	RA_DIR="/mnt/SDCARD/RetroArch"
	if [ "$use_igm" = "True" ]; then
		export RA_BIN="ra64.trimui_$PLATFORM"
	else
		export RA_BIN="retroarch.trimui"
	fi
	if [ "$CORE" = "uae4arm" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
	elif [ "$CORE" = "easyrpg" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR/lib-trimui:$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
	elif [ "$CORE" = "genesis_plus_gx" ] && [ "$DISPLAY_ASPECT_RATIO" = "16:9" ]; then
		use_gpgx_wide="$(get_config_value '.menuOptions."Emulator Settings".genesisPlusGXWide.selected' "False")"
		[ "$use_gpgx_wide" = "True" ] && CORE="genesis_plus_gx_wide"
	fi
	export CORE_DIR="$RA_DIR/.retroarch/cores64"

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
