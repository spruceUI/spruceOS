#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

WPA_FILE="/config/wpa_supplicant.conf"
TEMP_FILE="/config/wpa_supplicant_temp.conf"
MULTIPASS="/mnt/SDCARD/multipass.cfg"

# Check if the WPA file exists; create one if not
if [ ! -f "$WPA_FILE" ]; then
    log_message "Creating new $WPA_FILE"
    echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1" > "WPA_FILE"
fi

append_network_from_multipass() {
    echo ""
    echo "network={"
    echo "ssid=\"$1\""
    echo "psk=\"$2\""
    echo "}"
}

# If multipass.cfg exists at SD root and is properly formed, append its contents to the WPA file.
if [ -f /mnt/SDCARD/multipass.cfg ]; then
    . "$MULTIPASS"
    if [ -z "$ID_1" ] || [ -z "$PW_1" ]; then
        log_message "Primary SSID or password missing. Aborting multipass import"
    else
        for i in 1 2 3 4 5; do
            eval "ID=\$ID_$i"
            eval "PW=\$PW_$i"
            # Only consider new SSIDs for addition to the WPA file
            if ! grep -q "ssid=\"$ID\"" "$WPA_FILE"
                # SSID and PSK must be non-empty
                if [ -n "$ID" ] && [ -n "$PW" ]; then
                    append_network_from_multipass "$ID" "$PW" >> "$WIFI_FILE"
                    log_message "Network $ID added to wpa_supplicant.conf"
                fi
            fi
        done
        rm -f "$MULTIPASS"
    fi
else
    log_message "No multipass.cfg file found at SD root. Aborting multipass import"
fi

# Preserve the original WPA_FILE to TEMP_FILE on startup
cp "$WPA_FILE" "$TEMP_FILE"

remove_ssid() {

    SSID="$1"       # The SSID to remove
    FILE="$2"       # The file to process
    TMP_FILE=$(mktemp)

    # Process only complete network blocks and remove those matching the SSID
    awk -v ssid="$SSID" '
    BEGIN { in_network = 0; skip = 0; }

    /^network=/ { in_network = 1; block = ""; skip = 0; }
    /^}/ { in_network = 0; if (!skip) { print block; print $0; } next; }

    in_network {
        block = block $0 "\n";
        if ($0 ~ /ssid/ && $0 ~ ssid) { skip = 1; }
        next;
    }

    !in_network { print; }
    ' "$FILE" > "$TMP_FILE"

    # Overwrite the original file with the cleaned content
    mv "$TMP_FILE" "$FILE"

}

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
                
            # Remove all instances of the existing SSID
            remove_ssid "$NEW_SSID" "$TEMP_FILE"
            
            # Append the new network to the TEMP_FILE
            echo "$NEW_NETWORK" >> "$TEMP_FILE"
            log_message "WPA Watchdog: \"$NEW_SSID\" added."
    
        fi
        # Overwrite WPA_FILE with TEMP_FILE (safe because duplicate SSIDs are considered)
        cp "$TEMP_FILE" "$WPA_FILE"
    fi
}

# Monitor WPA file for new additions
while true; do
    # Wait for a modify event on the WPA file
    inotifywait -e modify -qq "$WPA_FILE"
    # Call the append function when a modification is detected
    log_message "WPA Watchdog: Detected change in $WPA_FILE"
    # Sleep required to handle over-detections by inotifywait
    sleep 1
    append_network
done
