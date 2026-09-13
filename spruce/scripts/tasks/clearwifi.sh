#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

WPA_HEADER="ctrl_interface=DIR=/var/run/wpa_supplicant
update_config=1"

if command -v nmcli >/dev/null 2>&1 && { device_manages_own_wifi || [ -z "$WPA_SUPPLICANT_FILE" ]; }; then
    # NetworkManager keeps its own profiles. Match on TYPE: an inactive profile has no DEVICE.
    nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r uuid type; do
        [ "$type" = "802-11-wireless" ] && nmcli connection delete uuid "$uuid" >/dev/null 2>&1
    done
elif [ -n "$WPA_SUPPLICANT_FILE" ]; then
    killall wpa_supplicant 2>/dev/null
    device_stop_dhcp_client
    sleep 1

    printf '%s\n' "$WPA_HEADER" > "$WPA_SUPPLICANT_FILE"

    # And from the pre-card-global locations, or enable_wifi's adoption sweep
    # would import every one of them straight back on the next boot and the
    # user's "forget all networks" would silently undo itself.
    for _legacy_conf in $WPA_LEGACY_CONFS; do
        [ -f "$_legacy_conf" ] || continue
        printf '%s\n' "$WPA_HEADER" > "$_legacy_conf"
        log_message "Wifi: cleared saved networks from $_legacy_conf"
    done

    # Bring WiFi back as the setting says, or the network list has no supplicant
    # to scan with. Detached, since enable_wifi can wait on the radio for seconds.
    ( enable_or_disable_wifi_per_system_json ) </dev/null >/dev/null 2>&1 &
fi

log_message "Wifi: All networks forgotten by request of user."
