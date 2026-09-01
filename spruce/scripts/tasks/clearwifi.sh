#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ -n "$WPA_SUPPLICANT_FILE" ] ; then
    # Bring the Wi-Fi interface down
    ifconfig wlan0 down
    sleep 2  
    killall wpa_supplicant
    device_stop_dhcp_client

    # Remove all networks
    echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1" | tee "$WPA_SUPPLICANT_FILE" "${WPA_SUPPLICANT_FILE}.tmp"

    # And from the pre-card-global locations, or enable_wifi's adoption sweep
    # would import every one of them straight back on the next boot and the
    # user's "forget all networks" would silently undo itself.
    for _legacy_conf in $WPA_LEGACY_CONFS; do
        [ -f "$_legacy_conf" ] || continue
        echo -e "ctrl_interface=DIR=/var/run/wpa_supplicant\nupdate_config=1" > "$_legacy_conf"
        log_message "Wifi: cleared saved networks from $_legacy_conf"
    done

    # Bring up interface to avoid issues with MainUI
    ifconfig wlan0 up
elif [ -d /storage/.config/NetworkManager/ ] ; then # NetworkManager
    rfkill block wifi

    NUUID=$(nmcli -t -f UUID,DEVICE connection show | grep wlan | cut -d : -f 1)
    echo "$NUUID" | while IFS= read -r line ; do
        nmcli connection delete uuid "$line"
    done

    rfkill unblock wifi
fi

log_message "Wifi: All networks forgotten by request of user."
