#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin"
    SETSHAREDMEM_PATH="$BIN_PATH/setsharedmem"
    SET_OR_CSET="set"
    NAME_QUALIFIER=""
    AMIXER_CONTROL="'Soft Volume Master'"
elif [ "$PLATFORM" = "Flip" ]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
    SETSHAREDMEM_PATH="$BIN_PATH/setsharedmem-flip"
    SET_OR_CSET="cset"
    NAME_QUALIFIER="name="
    AMIXER_CONTROL="'SPK Volume'"
else    # trimui
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
    SETSHAREDMEM_PATH="$BIN_PATH/setsharedmem-flip"     # this doesn't work yet. setsharedmem-flip is too high glibc
    SET_OR_CSET="set"                                   # need to double check this 
    NAME_QUALIFIER=""                                   # also need to check if this is necessary
    AMIXER_CONTROL="'Soft Volume Master'"
fi

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
    while true; do 
        sleep 0.3
        # fire volume_down in background
        # it makes sure to run whole volume_up function even volume_down_bg is killed
        volume_down &
    done
}

volume_up_bg() {
    while true; do 
        sleep 0.3
        # fire volume_up in background
        # it makes sure to run whole volume_up function even volume_up_bg is killed
        volume_up &
    done
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
        *"key $B_VOLDOWN 1"*) # VOLUMEDOWN key down
            kill $PID_DOWN 2&> /dev/null
            PID_DOWN=""
            volume_down # ensure fire the first run
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
