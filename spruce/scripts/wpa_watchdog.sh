#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

WPA_FILE="/config/wpa_supplicant.conf"
TEMP_FILE="/config/wpa_supplicant_temp.conf"

# Check if the WPA file exists
if [ ! -f "$WPA_FILE" ]; then
    echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1" > "WPA_FILE"
fi

# Preserve the original WPA_FILE to TEMP_FILE on startup
cp "$WPA_FILE" "$TEMP_FILE"

# Append a new network only if the SSID doesn't already exist
append_network() {
    # Extract the new network block (last added network)
    # This is adjusted for how MainUI adds networks to the wpa_supplicant in terms of # of lines
    NEW_NETWORK="$(tail -n 4 "$WPA_FILE" | grep -A 4 "network={")"
    
    # Extract the SSID from the new network block
    NEW_SSID=$(echo "$NEW_NETWORK" | grep 'ssid=' | sed 's/.*ssid="\([^"]*\)".*/\1/')
    
    # Check if NEW_NETWORK or NEW_SSID is empty
    if [ -z "$NEW_NETWORK" ] || [ -z "$NEW_SSID" ]; then
        # Must do the below to not lose networks!  MainUI resets wpa_supplicant to empty on failed attempt to add new network
        cp "$TEMP_FILE" "$WPA_FILE"
        return
    fi

    if [ -n "$NEW_SSID" ]; then
        # Check if the SSID already exists in the TEMP_FILE
        if grep "ssid=\"$NEW_SSID\"" "$TEMP_FILE" > /dev/null; then
            log_message "WPA Watchdog: SSID \"$NEW_SSID\" already exists, skipping append."         
        else
            # Append the new network to the TEMP_FILE
            echo "$NEW_NETWORK" >> "$TEMP_FILE"
            log_message "WPA Watchdog: \"$NEW_SSID\" added."

        fi
        # Overwrite WPA_FILE with TEMP_FILE (safe because duplicate SSIDs are considered)
        cp "$TEMP_FILE" "$WPA_FILE"
    fi
}

while true; do
    # Wait for a modify event on the WPA file
    inotifywait -e modify -qq "$WPA_FILE"
    # Call the append function when a modification is detected
    log_message "WPA Watchdog: Detected change in $WPA_FILE"
    # Sleep required to handle over-detections by inotifywait
    sleep 1
    append_network
done
