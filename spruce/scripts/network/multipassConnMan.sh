#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

MULTIPASS="/mnt/SDCARD/multipass.cfg"
CONNMAN_DIR="/storage/.cache/connman"

add_network_from_multipass() {
    echo "[Settings]"
    echo "AutoConnect = true"
    echo ""
    echo "[service_wifi_MULTIPASS_$4]"
    echo "Type = wifi"
    echo "Name = $1"
    echo "Passphrase = $2"
    if [ "$3" = "1" ]; then
        echo "Hidden = true"
    fi
}

# Check if multipass.cfg exists at SD root.
if [ -f $MULTIPASS ]; then
    . "$MULTIPASS" ### Import variables from multipass.cfg

    # Loop through the 5 potential SSID/PSK combos in multipass.cfg
    for i in 1 2 3 4 5; do
        eval "ID=\$ID_$i"
        eval "PW=\$PW_$i"
        eval "HIDDEN=\$HIDDEN_$i"

        # SSID and PSK must be non-empty to be evaluated
        if [ -n "$ID" ] && [ -n "$PW" ]; then
            # Check if given SSID already exists in connman folder
            if grep -rq "Name = $ID" $CONNMAN_DIR/ ; then
                # Find the file with the corresponding ID
                C_CFG=$(grep -r "Name = $ID" $CONNMAN_DIR/ | cut -d ":" -f1)

                # If the new PSK is not in the file already, update it
                if ! grep -xq "Passphrase = $PW" $C_CFG ; then
                    OLD_PW=$(grep "Passphrase =" $C_CFG | cut -d " " -f3)

                    sed -i "s|$(printf '%s' "$OLD_PW" | sed 's/[\/&]/\\&/g')|$(printf '%s' "$PW" | sed 's/[\/&]/\\&/g')|" "$C_CFG"
                    log_message "Password updated for network $ID"
                else ### both SSID and PSK found
                    log_message "Network $ID already has up-to-date password."
                fi
            else # SSID not found in the folder, so we add it
                NEW_CFG="${CONNMAN_DIR}/MULTIPASS_$i.config"
                add_network_from_multipass "$ID" "$PW" "$HIDDEN" "$i" >> "$NEW_CFG"
                log_message "Network $ID added to connman folder"
            fi

        else # either SSID or PSK is empty, so we skip that index
            log_message "Missing ID or PW for network $i in multipass.cfg. Skipping."
        fi
    done

    rm -f "$MULTIPASS" && log_message "Deleted $MULTIPASS"

else
    log_message "No multipass.cfg file found at SD root. Aborting multipass import"
fi
