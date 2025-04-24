#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BIN_PATH="/mnt/SDCARD/spruce/bin64"
[ "$PLATFORM" = "A30" ] && BIN_PATH="/mnt/SDCARD/spruce/bin"
# TODO: maybe rename these to setsharedmem-$PLATFORM if we need brick/tsp ones?
SETSHAREDMEM_PATH="$BIN_PATH/setsharedmem-flip"
[ "$PLATFORM" = "A30" ] && SETSHAREDMEM_PATH="$BIN_PATH/setsharedmem"
SET_OR_CSET="cset"
[ "$PLATFORM" = "A30" ] && SET_OR_CSET="set"
NAME_QUALIFIER="name="
[ "$PLATFORM" = "A30" ] && NAME_QUALIFIER=""
AMIXER_CONTROL="'SPK Volume'"
[ "$PLATFORM" = "A30" ] && AMIXER_CONTROL="'Soft Volume Master'"

START_DOWN=false

# Map the System Value to MainUI Volume level 
get_volume_level() {
  # TODO: does the a30 need the comma?
    value=$(amixer cget name="$AMIXER_CONTROL" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    case $value in
        $SYSTEM_VOLUME_0) echo 0 ;;
        $SYSTEM_VOLUME_1) echo 1 ;;
        $SYSTEM_VOLUME_2) echo 2 ;;
        $SYSTEM_VOLUME_3) echo 3 ;;
        $SYSTEM_VOLUME_4) echo 4 ;;
        $SYSTEM_VOLUME_5) echo 5 ;;
        $SYSTEM_VOLUME_6) echo 6 ;;
        $SYSTEM_VOLUME_7) echo 7 ;;
        $SYSTEM_VOLUME_8) echo 8 ;;
        $SYSTEM_VOLUME_9) echo 9 ;;
        $SYSTEM_VOLUME_10) echo 10 ;;
        $SYSTEM_VOLUME_11) echo 11 ;;
        $SYSTEM_VOLUME_12) echo 12 ;;
        $SYSTEM_VOLUME_13) echo 13 ;;
        $SYSTEM_VOLUME_14) echo 14 ;;
        $SYSTEM_VOLUME_15) echo 15 ;;
        $SYSTEM_VOLUME_16) echo 16 ;;
        $SYSTEM_VOLUME_17) echo 17 ;;
        $SYSTEM_VOLUME_18) echo 18 ;;
        $SYSTEM_VOLUME_19) echo 19 ;;
        $SYSTEM_VOLUME_20) echo 20 ;;
        *) echo 10 ;;
    esac
}

# Map the MainUI Volume level to System Value
map_mainui_volume_to_system_value() {
    case $1 in
        0) echo $SYSTEM_VOLUME_0 ;;
        1) echo $SYSTEM_VOLUME_1 ;;
        2) echo $SYSTEM_VOLUME_2 ;;
        3) echo $SYSTEM_VOLUME_3 ;;
        4) echo $SYSTEM_VOLUME_4 ;;
        5) echo $SYSTEM_VOLUME_5 ;;
        6) echo $SYSTEM_VOLUME_6 ;;
        7) echo $SYSTEM_VOLUME_7 ;;
        8) echo $SYSTEM_VOLUME_8 ;;
        9) echo $SYSTEM_VOLUME_9 ;;
        10) echo $SYSTEM_VOLUME_10 ;;
        11) echo $SYSTEM_VOLUME_11 ;;
        12) echo $SYSTEM_VOLUME_12 ;;
        13) echo $SYSTEM_VOLUME_13 ;;
        14) echo $SYSTEM_VOLUME_14 ;;
        15) echo $SYSTEM_VOLUME_15 ;;
        16) echo $SYSTEM_VOLUME_16 ;;
        17) echo $SYSTEM_VOLUME_17 ;;
        18) echo $SYSTEM_VOLUME_18 ;;
        19) echo $SYSTEM_VOLUME_19 ;;
        20) echo $SYSTEM_VOLUME_20 ;;
        *) ;;
    esac
}

nearest_system_brightness() {
    local input=$1
    local -a levels=(1 20 35 45 60 80 100 120 150 180 220)
    local nearest=${levels[0]}
    local min_diff=$((input - levels[0]))
    min_diff=${min_diff#-}  # absolute value

    for level in "${levels[@]}"; do
        local diff=$((input - level))
        diff=${diff#-}
        if (( diff < min_diff )); then
            min_diff=$diff
            nearest=$level
        fi
    done

    # Output the matching SYSTEM_BRIGHTNESS_X value
    for i in "${!levels[@]}"; do
        if [[ ${levels[i]} -eq $nearest ]]; then
            var="SYSTEM_BRIGHTNESS_$i"
            echo "${!var}"
            return
        fi
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

brightness_down() {
    # get current brightness level
    BRIGHTNESS_LV=$(get_brightness_level)
    
    # if value larger than zero
    if [ $BRIGHTNESS_LV -gt 0 ] ; then

        # update brightness level
        BRIGHTNESS_LV=$((BRIGHTNESS_LV-1))

        logger -p 15 -t "keymon[$$]" "brightness down"
        logger -p 15 -t "keymon[$$]" "setLCDBrightness $BRIGHTNESS_LV"
        
        # update screen brightness
        SYSTEM_BRIGHTNESS=$(map_brightness_to_system_value "$BRIGHTNESS_LV")
        echo "$SYSTEM_BRIGHTNESS" > "$DEVICE_BRIGHTNESS_PATH"

        # Update MainUI Config file
        sed -i "s/\"brightness\":\s*\([0-9]\|10\)/\"brightness\": $BRIGHTNESS_LV/" "$SYSTEM_JSON"

        logger -p 15 -t "keymon[$$]" "loadSystemState brightness changed 1 $BRIGHTNESS_LV"

        # write both level value to shared memory for MainUI to update its UI
        VOLUME_LV=$(get_volume_level)
        $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV"
    fi
}

brightness_up() {
    # get current brightness level
    BRIGHTNESS_LV=$(get_brightness_level)
    
    # if value larger than zero
    if [ $BRIGHTNESS_LV -lt 10 ] ; then

        # update brightness level
        BRIGHTNESS_LV=$((BRIGHTNESS_LV+1))

        logger -p 15 -t "keymon[$$]" "brightness up"
        logger -p 15 -t "keymon[$$]" "setLCDBrightness $BRIGHTNESS_LV"

        # update screen brightness
        SYSTEM_BRIGHTNESS=$(map_brightness_to_system_value "$BRIGHTNESS_LV")
        echo "$SYSTEM_BRIGHTNESS" > "$DEVICE_BRIGHTNESS_PATH"

        # Update MainUI Config file
        sed -i "s/\"brightness\":\s*\([0-9]\|10\)/\"brightness\": $BRIGHTNESS_LV/" "$SYSTEM_JSON"

        logger -p 15 -t "keymon[$$]" "loadSystemState brightness changed 1 $BRIGHTNESS_LV"
    
        # write both level value to shared memory for MainUI to update its UI
        VOLUME_LV=$(get_volume_level)
        $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV"
    fi
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

volume_down() {
    # get current volume level
    VOLUME_LV=$(get_volume_level)

    # if value larger than zero
    if [ $VOLUME_LV -gt 0 ] ; then

        # update brightness level
        VOLUME_LV=$((VOLUME_LV-1))

        # update screen brightness
        SYSTEM_VOLUME=$(map_mainui_volume_to_system_value "$VOLUME_LV")
        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $SYSTEM_VOLUME > /dev/null

        if [ "$PLATFORM" = "A30" ] ; then
          logger -p 15 -t "keymon[$$]" "volume down $VOLUME_LV"
        elif [ "$PLATFORM" = "Flip" ] ; then
          # attempt to tell mainui what we're setting volume too- this is what keymon does, but it doesn't seem to be helping
          # get graphical notifications on volume change
          logger -p 15 -t "keymon[$$]" "volume down 0ms, sleeped -1"
          logger -p 15 -t "keymon[$$]" "set volume $VOLUME_LV, $SYSTEM_VOLUME"
        else
          logger -p 15 -t "keymon[$$]" "volume down $VOLUME_LV"
        fi

        # write both level value to shared memory for MainUI to update its UI
        BRIGHTNESS_LV=$(get_brightness_level)
        $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV"
    fi
}

volume_up() {
    # get current volume level
    VOLUME_LV=$(get_volume_level)
    
    # if value larger than zero
    if [ $VOLUME_LV -lt 20 ] ; then

        # update brightness level
        VOLUME_LV=$((VOLUME_LV+1))

        # update screen brightness
        SYSTEM_VOLUME=$(map_mainui_volume_to_system_value "$VOLUME_LV")
        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $SYSTEM_VOLUME > /dev/null

        if [ "$PLATFORM" = "A30" ] ; then
          logger -p 15 -t "keymon[$$]" "volume up $VOLUME_LV"
        elif [ "$PLATFORM" = "Flip" ] ; then
          logger -p 15 -t "keymon[$$]" "volume up 0ms"
          logger -p 15 -t "keymon[$$]" "set volume $VOLUME_LV, $SYSTEM_VOLUME"
        else
          logger -p 15 -t "keymon[$$]" "volume up $VOLUME_LV"
        fi

        # write both level value to shared memory for MainUI to update its UI
        BRIGHTNESS_LV=$(get_brightness_level)
        $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV"
    fi
}

save_volume_to_config_file() {
    # get current levels
    VOLUME_LV=$(get_volume_level)

    # Update MainUI Config file
    sed -i "s/\"vol\":\s*\([0-9]*\)/\"vol\": $VOLUME_LV/" "$SYSTEM_JSON"
}

# scan all button input
EVENTS="$EVENT_PATH_KEYBOARD"
[ "$PLATFORM" = "Flip" ] && EVENTS="$EVENTS $EVENT_PATH_VOLUME"
$BIN_PATH/getevent $EVENTS | while read line; do

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
            save_volume_to_config_file
        ;;
        *"key $B_VOLUP 1"*) # VOLUMEUP key down
            kill $PID_UP 2&> /dev/null
            PID_DOWN=""
            volume_up # ensure fire the first run
            volume_up_bg &
            PID_UP=$!
        ;;
        *"key $B_VOLUP 0"*) # VOLUMEUP key up
            kill $PID_UP 2&> /dev/null
            PID_UP=""
            save_volume_to_config_file
        ;;
    esac
done
