#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

MULTIPASS="/mnt/SDCARD/multipass.cfg"
TEMP_FILE="${WPA_SUPPLICANT_FILE}.tmp"

# Check if the WPA file exists; create one if not
if [ ! -f "$WPA_SUPPLICANT_FILE" ]; then
    log_message "Creating new $WPA_SUPPLICANT_FILE"
    echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1" > "$WPA_SUPPLICANT_FILE"
fi

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