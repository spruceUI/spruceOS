#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

if ! check_and_connect_wifi; then
    log_and_display_message "No network connection. Connect to WiFi and try again."
    exit 1
fi

if ! pgrep syncthing >/dev/null; then
    start_syncthing_process
fi

config_file="$ST_DIR/config/config.xml"
attempt=0
while [ ! -f "$config_file" ] && [ "$attempt" -lt 30 ]; do
    sleep 1
    attempt=$((attempt + 1))
done

if [ ! -f "$config_file" ]; then
    log_and_display_message "Unable to start Syncthing. See spruce.log for details."
    exit 1
fi

exec /mnt/SDCARD/spruce/scripts/network/syncthing_sync_check.sh --monitor
