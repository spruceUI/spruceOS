#!/bin/sh

WATCHED_FILE="/config/joypad.config"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

while true; do
    # monitor the calibration file
    inotifywait -e modify "$WATCHED_FILE"
    log_message "File $WATCHED_FILE has been modified" -v

    # kill existing joystickinput process
    killall -TERM joystickinput

    # start new joystickinput process with new calibration values
    /mnt/SDCARD/spruce/bin/joystickinput /dev/ttyS2 /config/joypad.config -axis /dev/input/event4 -key /dev/input/event3 &

done
