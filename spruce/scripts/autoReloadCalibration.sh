#!/bin/sh

WATCHED_FILE="/config/joypad.config"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

sleep 0.3 ### wait long enough to create the virtual joypad

while true; do

    # restart joystickinput if calibration file exists
    if [ -f "$WATCHED_FILE" ]; then
        # kill existing joystickinput process
        killall -TERM joystickinput

        # start new joystickinput process with new calibration values
        /mnt/SDCARD/spruce/bin/joystickinput /dev/ttyS2 /config/joypad.config -axis /dev/input/event4 -key /dev/input/event3 &

        if pgrep MainUI >/dev/null ; then
            # send signal USR2 to joystickinput to switch to KEYBOARD MODE
            # this allows joystick to be used as DPAD in MainUI
            killall -USR2 joystickinput
        fi
    fi
    
    # avoid potential busy looping
    sleep 1

    if [ -f "$WATCHED_FILE" ]; then
        # monitor the calibration file if the file exists
        inotifywait -e modify "$WATCHED_FILE"
        log_message "File $WATCHED_FILE has been modified" -v
    else
        # monitor any event about calibration file like move or create if file does not exist
        inotifywait --include $(basename $WATCHED_FILE) $(dirname $WATCHED_FILE)
    fi
done
