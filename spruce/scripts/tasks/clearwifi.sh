#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Bring the Wi-Fi interface down
ifconfig wlan0 down
sleep 2  
killall wpa_supplicant
killall udhcpc

# Remove all networks
echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1" | tee "$WPA_SUPPLICANT_FILE" "${WPA_SUPPLICANT_FILE}.tmp"

# Bring up interface to avoid issues with MainUI
ifconfig wlan0 up

log_message "Wifi: All networks forgotten by request of user."
