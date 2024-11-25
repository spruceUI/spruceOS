#!/bin/sh

. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

if [ "$1" == "on" ] ; then
    update_setting "disableJoystick" "on"
    killall -q joystickinput

elif [ "$1" == "off" ] ; then
    update_setting "disableJoystick" "off"
    killall -q joystickinput
    sleep 0.5
    /mnt/SDCARD/spruce/bin/joystickinput /dev/ttyS2 /config/joypad.config -axis /dev/input/event4 -key /dev/input/event3 &
fi
