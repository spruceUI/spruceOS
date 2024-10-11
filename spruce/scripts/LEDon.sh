#!/bin/sh

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