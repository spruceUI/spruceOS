#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LOG_FILE="/var/log/messages"
BRIGHTNESS_PATTERN="setLCDBrightness"
SYS_BRIGHTNESS_PATH="/sys/devices/virtual/disp/disp/attr/lcdbl"
MAINUI_CONF="/config/system.json"
PROCESS_NAME="MainUI"
LAST_REPORTED_BRIGHTNESS=""

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
