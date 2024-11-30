#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LOG_FILE="/var/log/messages"
MAINUI_CONF_FILE="/config/system.json"
TEMP_FILE="/tmp/tmp.file"

BIN_PATH="/mnt/SDCARD/spruce/bin"
SYS_BRIGHTNESS_PATH="/sys/devices/virtual/disp/disp/attr/lcdbl"
START_DOWN=false

# Map the System Value to MainUI Volume level 
get_volume_level() {
    value=$(amixer cget name='Soft Volume Master' | grep  -o ": values=[0-9]*," | grep -o [0-9]*)
    case $value in
        0) echo 0 ;;
        12) echo 1 ;;
        25) echo 2 ;;
        38) echo 3 ;;
        51) echo 4 ;;
        63) echo 5 ;;
        78) echo 6 ;;
        89) echo 7 ;;
        102) echo 8 ;;
        114) echo 9 ;;
        127) echo 10 ;;
        140) echo 11 ;;
        153) echo 12 ;;
        165) echo 13 ;;
        178) echo 14 ;;
        191) echo 15 ;;
        204) echo 16 ;;
        216) echo 17 ;;
        229) echo 18 ;;
        242) echo 19 ;;
        255) echo 20 ;;
        *) echo 10 ;;
    esac
}

# Map the MainUI Volume level to System Value
map_mainui_volume_to_system_value() {
    case $1 in
        0) echo 0 ;;
        1) echo 12 ;;
        2) echo 25 ;;
        3) echo 38 ;;
        4) echo 51 ;;
        5) echo 63 ;;
        6) echo 78 ;;
        7) echo 89 ;;
        8) echo 102 ;;
        9) echo 114 ;;
        10) echo 127 ;;
        11) echo 140 ;;
        12) echo 153 ;;
        13) echo 165 ;;
        14) echo 178 ;;
        15) echo 191 ;;
        16) echo 204 ;;
        17) echo 216 ;;
        18) echo 229 ;;
        19) echo 242 ;;
        20) echo 255 ;;
        *) ;;
    esac
}

# Map the System Value to MainUI brightness level 
get_brightness_level() {
    value=$(cat "$SYS_BRIGHTNESS_PATH")
    case $value in
        2) echo 0 ;;
        8) echo 1 ;;
        18) echo 2 ;;
        32) echo 3 ;;
        50) echo 4 ;;
        72) echo 5 ;;
        98) echo 6 ;;
        128) echo 7 ;;
        162) echo 8 ;;
        200) echo 9 ;;
        255) echo 10 ;;
        *) echo 5 ;;
    esac
}

# Map the MainUI brightness level to System Value
map_brightness_to_system_value() {
    case $1 in
        0) echo 2 ;;
        1) echo 8 ;;
        2) echo 18 ;;
        3) echo 32 ;;
        4) echo 50 ;;
        5) echo 72 ;;
        6) echo 98 ;;
        7) echo 128 ;;
        8) echo 162 ;;
        9) echo 200 ;;
        10) echo 255 ;;
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
        echo "$SYSTEM_BRIGHTNESS" > "$SYS_BRIGHTNESS_PATH"

        # Update MainUI Config file
        sed -i "s/\"brightness\":\s*\([0-9]\|10\)/\"brightness\": $BRIGHTNESS_LV/" "$MAINUI_CONF_FILE"

        logger -p 15 -t "keymon[$$]" "loadSystemState brightness changed 1 $BRIGHTNESS_LV"

        # write both level value to shared memory for MainUI to update its UI
        VOLUME_LV=$(get_volume_level)
        $BIN_PATH/setsharedmem "$VOLUME_LV" "$BRIGHTNESS_LV"
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
        echo "$SYSTEM_BRIGHTNESS" > "$SYS_BRIGHTNESS_PATH"

        # Update MainUI Config file
        sed -i "s/\"brightness\":\s*\([0-9]\|10\)/\"brightness\": $BRIGHTNESS_LV/" "$MAINUI_CONF_FILE"

        logger -p 15 -t "keymon[$$]" "loadSystemState brightness changed 1 $BRIGHTNESS_LV"
    
        # write both level value to shared memory for MainUI to update its UI
        VOLUME_LV=$(get_volume_level)
        $BIN_PATH/setsharedmem "$VOLUME_LV" "$BRIGHTNESS_LV"
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
        amixer set 'Soft Volume Master' $SYSTEM_VOLUME > /dev/null

        logger -p 15 -t "keymon[$$]" "volume up $VOLUME_LV"

        # write both level value to shared memory for MainUI to update its UI
        BRIGHTNESS_LV=$(get_brightness_level)
        $BIN_PATH/setsharedmem "$VOLUME_LV" "$BRIGHTNESS_LV"
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
        amixer set 'Soft Volume Master' $SYSTEM_VOLUME > /dev/null

        logger -p 15 -t "keymon[$$]" "volume up $VOLUME_LV"

        # write both level value to shared memory for MainUI to update its UI
        BRIGHTNESS_LV=$(get_brightness_level)
        $BIN_PATH/setsharedmem "$VOLUME_LV" "$BRIGHTNESS_LV"
    fi
}

save_volume_to_config_file() {
    # get current levels
    VOLUME_LV=$(get_volume_level)

    # Update MainUI Config file
    sed -i "s/\"vol\":\s*\([0-9]*\)/\"vol\": $VOLUME_LV/" "$MAINUI_CONF_FILE"
}

# scan all button input
$BIN_PATH/getevent /dev/input/event3 | while read line; do

    # first print event code to log file
    logger -p 15 -t "keymon[$$]" $line

    # handle hotkeys and volume buttons
    case $line in
        *"key 1 28 1"*) # START key down
            START_DOWN=true
            logger -p 15 -t "keymon[$$]" "enter_pressed 1"
        ;;
        *"key 1 28 0"*) # START key up
            START_DOWN=false
            logger -p 15 -t "keymon[$$]" "enter_pressed 0"
        ;;
        *"key 1 97 1"*) # SELECT key down
            logger -p 15 -t "keymon[$$]" "rctrl_pressed 1"
        ;;
        *"key 1 97 0"*) # SELECT key up
            logger -p 15 -t "keymon[$$]" "rctrl_pressed 0"
        ;;
        *"key 1 15 1"*) # L1 key down
            if [ "$START_DOWN" = true ] ; then
                brightness_down
            fi
        ;;
        *"key 1 14 1"*) # R1 key down
            if [ "$START_DOWN" = true ] ; then
                brightness_up
            fi
        ;;
        *"key 1 114 1"*) # VOLUMEDOWN key down
            kill $PID_DOWN 2&> /dev/null
            PID_DOWN=""
            volume_down # ensure fire the first run
            volume_down_bg &
            PID_DOWN=$!
        ;;
        *"key 1 114 0"*) # VOLUMEDOWN key up
            kill $PID_DOWN 2&> /dev/null
            PID_DOWN=""
            save_volume_to_config_file
        ;;
        *"key 1 115 1"*) # VOLUMEUP key down
            kill $PID_UP 2&> /dev/null
            PID_DOWN=""
            volume_up # ensure fire the first run
            volume_up_bg &
            PID_UP=$!
        ;;
        *"key 1 115 0"*) # VOLUMEUP key up
            kill $PID_UP 2&> /dev/null
            PID_UP=""
            save_volume_to_config_file
        ;;
    esac
done