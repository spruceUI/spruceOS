#!/bin/sh

# This script is a wrapper to take action on an idle event sourced from:
# ./idlemon -p MainUI -t 30 -c 5 -s "/mnt/SDCARD/spruce/scripts/idlemon_chargingAction.sh" -i

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


if [ "$(device_get_charging_status)" = "Charging" ]; then
    turn_off_screen

    rm -f /tmp/ge_out 2>/dev/null
    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" > /tmp/ge_out &
    GE_PID=$!

    while true; do
        # Turn on the screen if USB is disconnected
        if [ "$(device_get_charging_status)" = "Discharging" ]; then
            break
        fi

        # Turn on the screen if any button is pressed
        if [ -s "/tmp/ge_out" ]; then
            break
        fi

        sleep 1
    done

    turn_on_screen
    kill "$GE_PID" 2>/dev/null
    exit 0
fi
