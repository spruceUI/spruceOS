#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

while true; do
    inotifywait -e modify "$SYSTEM_JSON"
    BLUETOOTH="$(jq -r '.bluetooth' "$SYSTEM_JSON")"
    if [ $BLUETOOTH -eq 1 ]; then
        touch /tmp/bluetooth_ready
    elif [ $BLUETOOTH -eq 0 ]; then
        rm -f /tmp/bluetooth_ready
    fi
    sleep 0.1
done
