#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

WIFI_FILE="/config/wpa_supplicant.conf"

begin_file() {
    echo "ctrl_interface=DIR=/var/run/wpa_supplicant"
    echo "update_config=1"
}

add_network() {
    echo ""
    echo "network={"
    echo "ssid=\"$1\""
    echo "psk=\"$2\""
    echo "priority=$3"
    echo "}"
}

if [ -f /mnt/SDCARD/wifi.cfg ]; then
    . /mnt/SDCARD/wifi.cfg
else
    log_message "No wifi.cfg file found at SD root. Aborting supplicant.sh"
    exit 1
fi

if [ -z "$ID_1" ] || [ -z "$PW_1" ]; then
    log_message "Primary SSID or password missing. Aborting supplicant.sh"
    exit 1
fi

rm -f "$WIFI_FILE"
touch "$WIFI_FILE"
begin_file >> "$WIFI_FILE"

for i in 1 2 3 4 5; do
    eval "ID=\$ID_$i"
    eval "PW=\$PW_$i"
    
    if [ -n "$ID" ] && [ -n "$PW" ]; then
        add_network "$ID" "$PW" "$i" >> "$WIFI_FILE"
        log_message "Network $ID added to wpa_supplicant.conf"
    fi
done

rm -f "/mnt/SDCARD/wifi.cfg"