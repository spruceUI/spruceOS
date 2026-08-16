#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# Shared button-action dispatch (perform_action), used by the top Home button
# via device_home_button_pressed on devices that have one (e.g. Smart Pro S).
. /mnt/SDCARD/spruce/scripts/button_actions.sh

START_DOWN=false

nearest_system_brightness() {
    input=$1
    levels="$SYSTEM_BRIGHTNESS_0 $SYSTEM_BRIGHTNESS_1 $SYSTEM_BRIGHTNESS_2 $SYSTEM_BRIGHTNESS_3 $SYSTEM_BRIGHTNESS_4 $SYSTEM_BRIGHTNESS_5 $SYSTEM_BRIGHTNESS_6 $SYSTEM_BRIGHTNESS_7 $SYSTEM_BRIGHTNESS_8 $SYSTEM_BRIGHTNESS_9 $SYSTEM_BRIGHTNESS_10"

    nearest=""
    min_diff=""

    for level in $levels; do
        diff=$((input - level))
        # absolute value
        if [ "$diff" -lt 0 ]; then
            diff=$(( -diff ))
        fi

        if [ -z "$min_diff" ] || [ "$diff" -lt "$min_diff" ]; then
            min_diff=$diff
            nearest=$level
        fi
    done

    # Find the index of the nearest level
    idx=0
    for level in $levels; do
        if [ "$level" -eq "$nearest" ]; then
            var="SYSTEM_BRIGHTNESS_$idx"
            eval "echo \${$var}"
            return
        fi
        idx=$((idx + 1))
    done
}

# Map the System Value to MainUI brightness level 
get_brightness_level() {
    value=$(cat "$DEVICE_BRIGHTNESS_PATH")
    nearest=$(nearest_system_brightness "$value")
    case $nearest in
        $SYSTEM_BRIGHTNESS_0) echo 0 ;;
        $SYSTEM_BRIGHTNESS_1) echo 1 ;;
        $SYSTEM_BRIGHTNESS_2) echo 2 ;;
        $SYSTEM_BRIGHTNESS_3) echo 3 ;;
        $SYSTEM_BRIGHTNESS_4) echo 4 ;;
        $SYSTEM_BRIGHTNESS_5) echo 5 ;;
        $SYSTEM_BRIGHTNESS_6) echo 6 ;;
        $SYSTEM_BRIGHTNESS_7) echo 7 ;;
        $SYSTEM_BRIGHTNESS_8) echo 8 ;;
        $SYSTEM_BRIGHTNESS_9) echo 9 ;;
        $SYSTEM_BRIGHTNESS_10) echo 10 ;;
        *) echo 5 ;;
    esac
}

# Map the MainUI brightness level to System Value
map_brightness_to_system_value() {
    case $1 in
        0) echo $SYSTEM_BRIGHTNESS_0 ;;
        1) echo $SYSTEM_BRIGHTNESS_1 ;;
        2) echo $SYSTEM_BRIGHTNESS_2 ;;
        3) echo $SYSTEM_BRIGHTNESS_3 ;;
        4) echo $SYSTEM_BRIGHTNESS_4 ;;
        5) echo $SYSTEM_BRIGHTNESS_5 ;;
        6) echo $SYSTEM_BRIGHTNESS_6 ;;
        7) echo $SYSTEM_BRIGHTNESS_7 ;;
        8) echo $SYSTEM_BRIGHTNESS_8 ;;
        9) echo $SYSTEM_BRIGHTNESS_9 ;;
        10) echo $SYSTEM_BRIGHTNESS_10 ;;
        *) ;;
    esac
}


volume_down_bg() {
    trap 'set_volume "$CURR_VOLUME"' EXIT # This is called when the subprocess is killed
    while true; do
        sleep 0.3
        if [ $CURR_VOLUME -gt 0 ]; then
            CURR_VOLUME=$((${CURR_VOLUME} - 1))
            set_volume "$CURR_VOLUME" false &
        fi
    done
}

volume_up_bg() {
    trap 'set_volume "$CURR_VOLUME"' EXIT # This is called when the subprocess is killed
    while true; do
        sleep 0.3
        if [ $CURR_VOLUME -lt 20 ]; then
            CURR_VOLUME=$((${CURR_VOLUME} + 1))
            set_volume "$CURR_VOLUME" false &
        fi
    done
}

# Button Settings > Brightness hotkey. Read at press time rather than cached at
# startup so a change in the settings menu applies without a reboot. Both
# callers below put their cheap test first, so the jq call only happens for a
# press that could actually be a brightness chord.
brightness_hotkey() {
    get_config_value '.menuOptions."Button Settings".brightnessHotkey.selected' "Both"
}

start_lr_brightness_active() {
    case "$(brightness_hotkey)" in
        "Start + L/R" | "Both") return 0 ;;
        *) return 1 ;;
    esac
}

# While MENU is held, vol_up/vol_down step brightness instead of volume.
# /tmp/menubtn is the held-state flag homebutton_watchdog.sh sets; that script is
# a separate process, so this is the only way for this one to know MENU is down.
# Nothing else needs to be disabled to make room for this chord: a volume key
# pressed while MENU is held already runs cancel_menu_hold in
# homebutton_watchdog.sh, which kills the pending hold-home timer and suppresses
# the tap-home action, so the chord costs none of the other MENU actions.
menu_vol_brightness_active() {
    [ -e /tmp/menubtn ] || return 1
    case "$(brightness_hotkey)" in
        "Menu + Vol" | "Both") return 0 ;;
        *) return 1 ;;
    esac
}

brightness_down_bg() {
    while true; do
        sleep 0.3
        brightness_down
    done
}

brightness_up_bg() {
    while true; do
        sleep 0.3
        brightness_up
    done
}

take_screenshot_bg() {
    timestamp=$(date '+_%Y.%m.%d_%H.%M.%S.%N.png')
    ss_name="/mnt/SDCARD/Saves/screenshots/$PLATFORM$timestamp"

    vibrate &
    take_screenshot "$ss_name"
}

# Setup global screenshot shortcut
# Read both locations. The option lived under System Settings and moved to
# Button Settings in d0956be41, but only in the shipped config - an installed
# card keeps the old location until an update merges the new default in, and a
# card that has never been updated keeps it indefinitely. This reader was left
# on the old path, and because get_config_value falls back to its default on a
# missing path - the same L2+R2+Y - the setting looked like it worked while
# being ignored, so choosing X, DOWN or Off silently did nothing.
#
# Try the new location first so it wins once a config has both, and fall back to
# the old one rather than to the default, which would discard a user's choice.
SS_SHORTCUT="$(get_config_value '.menuOptions."Button Settings".globalScreenshotShortcut.selected' "")"
[ -n "$SS_SHORTCUT" ] || SS_SHORTCUT="$(get_config_value '.menuOptions."System Settings".globalScreenshotShortcut.selected' "L2+R2+Y")"
SS_B1=$B_L2
SS_B2=$B_R2

case "$SS_SHORTCUT" in
    "L2+R2+Y")
        SS_B3=$B_Y
        ;;
    "L2+R2+X")
        SS_B3=$B_X
        ;;
    "L2+R2+DOWN")
        SS_B3=$B_DOWN
        ;;
    "Off")
        SS_B1="NULL"
        SS_B2="NULL"
        SS_B3="NULL"
        ;;
esac

# Build the press/release patterns for one combo button.
#
# The matches below are written as "key $VAR <value>", which assumes a B_* holds
# just "type code". Most buttons do, but analog triggers and hats bake the value
# in - B_L2="3 2 255" on the Flip and the TrimUI line, B_DOWN="3 17 1" on nearly
# everything - so the pattern ended up with two values and could never match a
# real getevent line. Measured on a Flip: L2 emits "key 3 2 255" while the
# watchdog was looking for "key 3 2 255 1". That left SS_B1_DOWN and SS_B2_DOWN
# permanently false, so the one leg that did match could never fire, and every
# screenshot shortcut was dead on 7 devices (9 for the DOWN variant).
#
# Derive both patterns from the spec instead of assuming its shape:
#   "T C"    -> press "key T C 1", release "key T C 0"   (unchanged behaviour)
#   "T C V"  -> press "key T C V", release "key T C 0"
#
# Anything else - "NULL" when the shortcut is Off, "DOESNT_EXIST", or the Mini's
# literal "B_L2" placeholder for triggers it does not have - gets a sentinel that
# cannot appear in the stream. It must never be empty: an empty pattern makes
# *""* match every line and would fire screenshots continuously.
ss_set_patterns() {
    _ss_var="$2"
    case "$(echo $_ss_var | wc -w)" in
        2)
            eval "${1}_PRESS=\"key \$_ss_var 1\""
            eval "${1}_REL=\"key \$_ss_var 0\""
            ;;
        3)
            eval "${1}_PRESS=\"key \$_ss_var\""
            eval "${1}_REL=\"key $(echo $_ss_var | awk '{print $1, $2, 0}')\""
            ;;
        *)
            eval "${1}_PRESS='__ss_disabled__'"
            eval "${1}_REL='__ss_disabled__'"
            ;;
    esac
}

ss_set_patterns SS_B1 "$SS_B1"
ss_set_patterns SS_B2 "$SS_B2"
ss_set_patterns SS_B3 "$SS_B3"

SS_B1_DOWN=false
SS_B2_DOWN=false
SS_B3_DOWN=false

# scan all button input
EVENTS="$EVENT_PATH_READ_INPUTS_SPRUCE"
[ -n "$EVENT_PATH_VOLUME" ] && [ -c "$EVENT_PATH_VOLUME" ] && EVENTS="$EVENTS $EVENT_PATH_VOLUME"
getevent $EVENTS | while read line; do
    # first print event code to log file
    # handle hotkeys and volume buttons
    case $line in
        *"key $B_START 1"*) # START key down
            START_DOWN=true
        ;;
        *"key $B_START 0"*) # START key up
            START_DOWN=false
        ;;
        *"key $B_L1 1"*) # L1 key down
            if [ "$START_DOWN" = true ] && start_lr_brightness_active ; then
                brightness_down
            fi
        ;;
        *"key $B_R1 1"*) # R1 key down
            if [ "$START_DOWN" = true ] && start_lr_brightness_active ; then
                brightness_up
            fi
        ;;
        *"$SS_B1_PRESS"*) # Screenshot key 1 down
            SS_B1_DOWN=true
            if [ "$SS_B2_DOWN" = true ] && [ "$SS_B3_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"$SS_B1_REL"*) # Screenshot key 1 up
            SS_B1_DOWN=false
        ;;
        *"$SS_B2_PRESS"*) # Screenshot key 2 down
            SS_B2_DOWN=true
            if [ "$SS_B1_DOWN" = true ] && [ "$SS_B3_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"$SS_B2_REL"*) # Screenshot key 2 up
            SS_B2_DOWN=false
        ;;
        *"$SS_B3_PRESS"*) # Screenshot key 3 down
            SS_B3_DOWN=true
            if [ "$SS_B1_DOWN" = true ] && [ "$SS_B2_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"$SS_B3_REL"*) # Screenshot key 3 up
            SS_B3_DOWN=false
        ;;
        *"key $B_VOLDOWN 1"*) # VOLUMEDOWN key down
            kill $PID_DOWN 2&> /dev/null
            PID_DOWN=""
            [ -n "$PID_UP" ] && kill "$PID_UP" 2>/dev/null
            PID_UP=""

            if menu_vol_brightness_active; then
                brightness_down # ensure fire the first run
                brightness_down_bg &
                PID_DOWN=$!
            else
                volume_down # ensure fire the first run

                CURR_VOLUME=$(get_volume_level)
                volume_down_bg &
                PID_DOWN=$!
            fi
        ;;
        *"key $B_VOLDOWN 0"*) # VOLUMEDOWN key up
            kill $PID_DOWN 2&> /dev/null
            PID_DOWN=""
        ;;
        *"key $B_VOLUP 1"*) # VOLUMEUP key down
            kill $PID_UP 2&> /dev/null
            PID_UP=""
            [ -n "$PID_DOWN" ] && kill "$PID_DOWN" 2>/dev/null
            PID_DOWN=""

            if menu_vol_brightness_active; then
                brightness_up # ensure fire the first run
                brightness_up_bg &
                PID_UP=$!
            else
                volume_up # ensure fire the first run

                CURR_VOLUME=$(get_volume_level)
                volume_up_bg &
                PID_UP=$!
            fi
        ;;
        *"key $B_VOLUP 0"*) # VOLUMEUP key up
            kill $PID_UP 2&> /dev/null
            PID_UP=""
        ;;
        *"key $B_HOME 1"*) # Home Button Pressed
            device_home_button_pressed
        ;;
    esac
done
