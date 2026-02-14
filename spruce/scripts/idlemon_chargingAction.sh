#!/bin/sh

# This script is a wrapper to take action on an idle event sourced from:
# ./idlemon -p MainUI -t 30 -c 5 -s "/mnt/SDCARD/spruce/scripts/idlemon_chargingAction.sh" -i

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Turn off screen and wait for input to wake up
if [ "$(device_get_charging_status)" = "Charging" ] ; then
    turn_off_screen

    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" | while read -r _; do
        turn_on_screen
        exit 0
    done
fi
