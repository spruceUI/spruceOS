#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

while true; do
    inotifywait -e modify "$SYSTEM_JSON"
    BLUETOOTH="$(jq -r '.bluetooth' "$SYSTEM_JSON")"
    if [ $BLUETOOTH -eq 1 ]; then
        /usr/bin/hciconfig hci0 up
        /usr/bin/bluealsa -p a2dp-source &
        touch /tmp/bluetooth_ready
    fi
    sleep 0.1
done
