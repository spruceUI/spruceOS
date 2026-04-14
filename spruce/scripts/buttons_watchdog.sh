#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

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

take_screenshot_bg() {
    timestamp=$(date '+_%Y.%m.%d_%H.%M.%S.%N.png')
    ss_name="/mnt/SDCARD/Saves/screenshots/$PLATFORM$timestamp"

    vibrate &
    take_screenshot "$ss_name"
}

# Setup global screenshot shortcut
SS_SHORTCUT="$(get_config_value '.menuOptions."System Settings".globalScreenshotShortcut.selected' "L2+R2+Y")"
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
            if [ "$START_DOWN" = true ] ; then
                brightness_down
            fi
        ;;
        *"key $B_R1 1"*) # R1 key down
            if [ "$START_DOWN" = true ] ; then
                brightness_up
            fi
        ;;
        *"key $SS_B1 1"*) # Screenshot key 1 down
            SS_B1_DOWN=true
            if [ "$SS_B2_DOWN" = true ] && [ "$SS_B3_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"key $SS_B1 0"*) # Screenshot key 1 up
            SS_B1_DOWN=false
        ;;
        *"key $SS_B2 1"*) # Screenshot key 2 down
            SS_B2_DOWN=true
            if [ "$SS_B1_DOWN" = true ] && [ "$SS_B3_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"key $SS_B2 0"*) # Screenshot key 2 up
            SS_B2_DOWN=false
        ;;
        *"key $SS_B3 1"*) # Screenshot key 3 down
            SS_B3_DOWN=true
            if [ "$SS_B1_DOWN" = true ] && [ "$SS_B2_DOWN" = true ] ; then
                take_screenshot_bg &
            fi
        ;;
        *"key $SS_B3 0"*) # Screenshot key 3 up
            SS_B3_DOWN=false
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

        *"key $B_L3 1"*) # L3 Button Pressed
            device_L3_button_pressed
        ;;
        *"key $B_L3 0"*) # L3 Button Released
            device_L3_button_released
        ;;
        *"key $B_R3 1"*) # R3 Button Pressed
            device_R3_button_pressed
        ;;
        *"key $B_R3 0"*) # R3 Button Released
            device_R3_button_released
        ;;        
    esac
done
