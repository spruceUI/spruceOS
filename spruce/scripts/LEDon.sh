#!/bin/sh

# chech flag and print setting value (without newline) as return value
# this function is placed before loading helping functions for fast checking
if [ "$1" == "check" ] ; then
    if [ -f "/mnt/SDCARD/spruce/flags/ledon.lock" ]; then
        echo -n "Always on"
    elif [ -f "/mnt/SDCARD/spruce/flags/tlon.lock" ]; then
        echo -n "On in menu only"
    else
        echo -n "Always off"
    fi
    return 0
fi

# Source the helper functions
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$1" == "on" ] ; then
    flag_remove "tlon"
    flag_add "ledon"
elif [ "$1" == "off" ] ; then
    flag_remove "tlon"
    flag_remove "ledon"
elif [ "$1" == "menu" ] ; then
    flag_add "tlon"
    flag_remove "ledon"
fi