#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

START_DOWN=false
Y_DOWN=false
R2_DOWN=false
L2_DOWN=false

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

take_screenshot_bg() {
    timestamp=$(date '+_%Y.%m.%d_%H.%M.%S.%N.png')
    ss_name="/mnt/SDCARD/Saves/screenshots/$PLATFORM$timestamp"

    vibrate &
    take_screenshot "$ss_name" false
}

# scan all button input
EVENTS="$EVENT_PATH_READ_INPUTS_SPRUCE"
[ -n "$EVENT_PATH_VOLUME" ] && [ -c "$EVENT_PATH_VOLUME" ] && EVENTS="$EVENTS $EVENT_PATH_VOLUME"
getevent $EVENTS | while read line; do
    # first print event code to log file
    logger -p 15 -t "keymon[$$]" "$line"
    # handle hotkeys and volume buttons
    case $line in
        *"key $B_START 1"*) # START key down
            START_DOWN=true
            logger -p 15 -t "keymon[$$]" "enter_pressed 1"
        ;;
        *"key $B_START 0"*) # START key up
            START_DOWN=false
            logger -p 15 -t "keymon[$$]" "enter_pressed 0"
        ;;
        *"key $B_SELECT 1"*) # SELECT key down
            logger -p 15 -t "keymon[$$]" "rctrl_pressed 1"
        ;;
        *"key $B_SELECT 0"*) # SELECT key up
            logger -p 15 -t "keymon[$$]" "rctrl_pressed 0"
        ;;
        *"key $B_L1 1"*) # L1 key down
            if [ "$START_DOWN" = true ] ; then
                brightness_down
            fi
        ;;
        *"key $B_R1 1"*) # R1 key down
            if [ "$START_DOWN" = true ] ; then
                brightness_up
            fi
        ;;
        *"key $B_Y 1"*) # Y key down
            Y_DOWN=true
            if [ "$L2_DOWN" = true ] && [ "$R2_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"key $B_Y 0"*) # Y key up
            Y_DOWN=false
        ;;
        *"key $B_L2 1"*) # L2 key down
            L2_DOWN=true
            if [ "$Y_DOWN" = true ] && [ "$R2_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"key $B_L2 0"*) # L2 key up
            L2_DOWN=false
        ;;
        *"key $B_R2 1"*) # R2 key down
            R2_DOWN=true
            if [ "$Y_DOWN" = true ] && [ "$L2_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"key $B_R2 0"*) # R2 key up
            R2_DOWN=false
        ;;
        *"key $B_VOLDOWN 1"*) # VOLUMEDOWN key down
            kill $PID_DOWN 2&> /dev/null
            PID_DOWN=""

            volume_down # ensure fire the first run

            CURR_VOLUME=$(get_volume_level)
            volume_down_bg &
            PID_DOWN=$!
        ;;
        *"key $B_VOLDOWN 0"*) # VOLUMEDOWN key up
            kill $PID_DOWN 2&> /dev/null
            PID_DOWN=""
        ;;
        *"key $B_VOLUP 1"*) # VOLUMEUP key down
            kill $PID_UP 2&> /dev/null
            PID_UP=""

            volume_up # ensure fire the first run

            CURR_VOLUME=$(get_volume_level)
            volume_up_bg &
            PID_UP=$!
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
