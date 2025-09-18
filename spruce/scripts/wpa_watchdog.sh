#!/bin/sh

##### GENERAL #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" != "Flip" ]; then
    log_message "wpa_watchdog disabled due to running on the flip"
    exit 0
fi

MULTIPASS="/mnt/SDCARD/multipass.cfg"
TEMP_FILE="${WPA_SUPPLICANT_FILE}.tmp"

# Check if the WPA file exists; create one if not
if [ ! -f "$WPA_SUPPLICANT_FILE" ]; then
    log_message "Creating new $WPA_SUPPLICANT_FILE"
    echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1" > "$WPA_SUPPLICANT_FILE"
fi

##### MULTIPASS.CFG #####

append_network_from_multipass() {
    echo ""
    echo "network={"
    echo "ssid=\"$1\""
    echo "psk=\"$2\""
    if [ "$3" = "1" ]; then
        echo "scan_ssid=$3"
    fi
    echo "}"
}

get_psk() {
    ssid="$1"
    found=0

    while IFS= read -r line; do
        if [ "$found" -eq 1 ]; then
            # The PSK line follows the SSID line
            if echo "$line" | grep -q '^psk='; then
                echo "${line#psk=}"
                return
            fi
            found=0
        fi

        # Check for the SSID line
        if echo "$line" | grep -q "ssid=\"$ssid\""; then
            found=1
        fi
    done < "$WPA_SUPPLICANT_FILE"
}

# Check if multipass.cfg exists at SD root.
if [ -f /mnt/SDCARD/multipass.cfg ]; then
    . "$MULTIPASS" ### Import variables from multipass.cfg

    # Loop through the 5 potential SSID/PSK combos in multipass.cfg
    for i in 1 2 3 4 5; do
        eval "ID=\$ID_$i"
        eval "PW=\$PW_$i"
        eval "HIDDEN=\$HIDDEN_$i"

        # SSID and PSK must be non-empty to be evaluated
        if [ -n "$ID" ] && [ -n "$PW" ]; then

            # Check if given SSID already exists in wpa_supplicant.conf
            if grep -q "ssid=\"$ID\"" "$WPA_SUPPLICANT_FILE"; then
            
                # If SSID but not PSK already found, update PSK
                if ! grep -q "psk=\"$PW\"" "$WPA_SUPPLICANT_FILE"; then
                    OLD_PW="$(get_psk "$ID")"
                    sed -i "s|$(printf '%s' "$OLD_PW" | sed 's/[\/&]/\\&/g')|$(printf '%s' "$PW" | sed 's/[\/&]/\\&/g')|" "$WPA_SUPPLICANT_FILE"
                    log_message "Password updated for network $ID"

                else ### both SSID and PSK found
                    log_message "Network $ID already has up-to-date password."
                fi

            else ### SSID not found in wpa_supplicant.conf, so we add it
                append_network_from_multipass "$ID" "$PW" "$HIDDEN" >> "$WPA_SUPPLICANT_FILE"
                log_message "Network $ID added to wpa_supplicant.conf"
            fi

        else ### either SSID or PSK is empty, so we skip that index
            log_message "Missing ID or PW for network $i in multipass.cfg. Skipping."
        fi
    done
    
    rm -f "$MULTIPASS" && log_message "Deleted $MULTIPASS"

else
    log_message "No multipass.cfg file found at SD root. Aborting multipass import"
fi

##### MAINUI WI-FI GUI #####

# Preserve the original WPA_SUPPLICANT_FILE to TEMP_FILE on startup
cp "$WPA_SUPPLICANT_FILE" "$TEMP_FILE"

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
    NEW_NETWORK="$(tail -n 4 "$WPA_SUPPLICANT_FILE" | grep -A 4 "network={")"
    
    # Extract the SSID from the new network block
    NEW_SSID=$(echo "$NEW_NETWORK" | grep 'ssid=' | sed 's/.*ssid="\([^"]*\)".*/\1/')
    
    # Check if NEW_NETWORK or NEW_SSID is empty
    if [ -z "$NEW_NETWORK" ] || [ -z "$NEW_SSID" ]; then
        # Must do the below to not lose networks!  MainUI resets wpa_supplicant to empty on failed attempt to add new network
        cp "$TEMP_FILE" "$WPA_SUPPLICANT_FILE"
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
        else
            # SSID not found, append the new network to TEMP_FILE
            echo "$NEW_NETWORK" >> "$TEMP_FILE"
            log_message "WPA Watchdog: \"$NEW_SSID\" added."
        fi
        # Overwrite WPA_SUPPLICANT_FILE with TEMP_FILE (safe because duplicate SSIDs are considered)
        cp "$TEMP_FILE" "$WPA_SUPPLICANT_FILE"
    fi
}

# Monitor WPA file for new additions
while true; do
    # Wait for a modify event on the WPA file
    inotifywait -e modify -qq "$WPA_SUPPLICANT_FILE"
    # Call the append function when a modification is detected
    log_message "WPA Watchdog: Detected change in $WPA_SUPPLICANT_FILE"
    # Sleep required to handle over-detections by inotifywait
    sleep 1
    append_network
done
