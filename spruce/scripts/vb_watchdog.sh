#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LOG_FILE="/var/log/messages"
VOLUME_PATTERN="volume change"
BRIGHTNESS_PATTERN="setLCDBrightness"
SYS_BRIGHTNESS_PATH="/sys/devices/virtual/disp/disp/attr/lcdbl"
MAINUI_CONF="/config/system.json"
PROCESS_NAME="MainUI"
LAST_REPORTED_VOLUME=""
LAST_REPORTED_BRIGHTNESS=""

# Map the System Value to MainUI Volume level
map_system_value_to_mainui_volume() {
    case $1 in
        0) echo 0 ;;
        12) echo 1 ;;
        25) echo 2 ;;
        38) echo 3 ;;
        51) echo 4 ;;
        63) echo 5 ;;
        76) echo 6 ;;
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
        *) ;;
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

tail -F "$LOG_FILE" | while read line; do
    # Check for volume change
    if echo "$line" | grep -q "$VOLUME_PATTERN"; then
        # Extract the volume value
        CURRENT_VOLUME=$(amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%')

        # If the new volume value is different from the last reported one
        if [ "$CURRENT_VOLUME" != "$LAST_REPORTED_VOLUME" ]; then
            LAST_REPORTED_VOLUME="$CURRENT_VOLUME"

            # Map the system volume level to the mainui value
            MAINUI_VOLUME=$(map_system_value_to_mainui_volume "$CURRENT_VOLUME")
            
            #if ! pgrep "$PROCESS_NAME" > /dev/null; then
                # Update MainUI Conf    
                sed -i "s/\"vol\":\s*\([0-9]\|1[0-9]\|2[0-2]\)/\"vol\": $MAINUI_VOLUME/" "$MAINUI_CONF"
            #fi
        fi
    fi

    # Check for brightness change
    if echo "$line" | grep -q "$BRIGHTNESS_PATTERN"; then
        # Extract the brightness value (assumed to be the last field in the log entry)
        CURRENT_BRIGHTNESS=$(echo "$line" | awk '{print $NF}')

        # If the new brightness value is different from the last reported one
        if [ "$CURRENT_BRIGHTNESS" != "$LAST_REPORTED_BRIGHTNESS" ]; then
            LAST_REPORTED_BRIGHTNESS="$CURRENT_BRIGHTNESS"

            # Map the brightness level to the system value
            SYSTEM_BRIGHTNESS=$(map_brightness_to_system_value "$CURRENT_BRIGHTNESS")
            
            if ! pgrep "$PROCESS_NAME" > /dev/null; then
                # Write the system brightness value to device
                echo "$SYSTEM_BRIGHTNESS" > "$SYS_BRIGHTNESS_PATH"
                
                # Update MainUI Conf
                sed -i "s/\"brightness\":\s*\([0-9]\|10\)/\"brightness\": $CURRENT_BRIGHTNESS/" "$MAINUI_CONF"
            fi
        fi
    fi
done
