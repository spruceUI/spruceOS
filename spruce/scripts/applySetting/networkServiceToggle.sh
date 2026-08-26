#!/bin/sh
# Apply a Network Settings service toggle (Enable Samba / Enable SSH /
# Enable WiFi File Transfer / Enable Syncthing) immediately, instead of
# waiting for networkservices.sh's own connect loop to notice on its next
# wake, or for a reboot.
#
# Usage: networkServiceToggle.sh <samba|ssh|sftpgo|syncthing> <True|False>
#
# Wired up as each setting's changeCmd. PyUI's set_menu_option() saves the
# newly-selected value to spruce-config.json before running changeCmd (see
# CfwSystemConfig.set_menu_option) and appends that value as the last
# argument, so $2 here is already current.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sftpgoFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

SERVICE="$1"
ENABLED="$2"

case "$SERVICE" in
    samba)     PROC_NAME="smbd" ;;
    ssh)       PROC_NAME="$(get_ssh_service_name)" ;;
    sftpgo)    PROC_NAME="$(get_sftp_service_name)" ;;
    syncthing) PROC_NAME="syncthing" ;;
    *)
        log_message "networkServiceToggle: unknown service '$SERVICE'"
        exit 1
        ;;
esac

start_service() {
    case "$SERVICE" in
        samba)     start_samba_process ;;
        ssh)       start_ssh_process ;;
        sftpgo)    start_sftpgo_process ;;
        syncthing) start_syncthing_process ;;
    esac
}

stop_service() {
    case "$SERVICE" in
        samba)     stop_samba_process ;;
        ssh)       stop_ssh_process ;;
        sftpgo)    stop_sftpgo_process ;;
        syncthing) stop_syncthing_process ;;
    esac
}

if [ "$ENABLED" != "True" ]; then
    if pgrep "$PROC_NAME" >/dev/null; then
        log_message "networkServiceToggle: stopping $SERVICE (disabled via Settings)"
        stop_service
    fi
    exit 0
fi

# Only start right away if WiFi is actually connected -- otherwise leave it to
# networkservices.sh's own connect loop for whenever it does connect, same as
# at boot (it reads this same setting fresh once the network comes up).
if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 1 ] && network_is_connected true; then
    if ! pgrep "$PROC_NAME" >/dev/null; then
        log_message "networkServiceToggle: starting $SERVICE (enabled via Settings, WiFi already connected)"
        start_service
    fi
fi
