#!/bin/sh

    # read joystick raw data from serial input and apply calibration,
    # then send analog input to /dev/input/event4 when in ANALOG_MODE (this is default)
    # and send keyboard input to /dev/input/event3 when in KEYBOARD_MODE.
    # Please send kill signal USR1 to switch to ANALOG_MODE
    # and send kill signal USR2 to switch to KEYBOARD_MODE

WATCHED_FILE="/config/joypad.config"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

sleep 0.3 ### wait long enough to create the virtual joypad

if [ ! -f "$WATCHED_FILE" ]; then
    log_message "File $WATCHED_FILE does not exist. Exiting."
    touch "$WATCHED_FILE"
fi

while true; do

    # restart joystickinput if calibration file exists
    if [ -f "$WATCHED_FILE" ]; then
        # kill existing joystickinput process
        killall -q -TERM joystickinput

        # start new joystickinput process with new calibration values
        disable_joystick="$(get_config_value '.menuOptions."System Settings".disableJoystick.selected' "False")"
        if [ "$disable_joystick" = "False" ]; then
            /mnt/SDCARD/spruce/bin/joystickinput /dev/ttyS2 /config/joypad.config -axis $EVENT_PATH_JOYPAD -key $EVENT_PATH_KEYBOARD &
        fi

        if pgrep MainUI >/dev/null; then
            # send signal USR2 to joystickinput to switch to KEYBOARD MODE
            # this allows joystick to be used as DPAD in MainUI
            killall -q -USR2 joystickinput
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
