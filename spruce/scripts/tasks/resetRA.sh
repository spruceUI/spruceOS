#!/bin/sh
if [ "$1" == "0" ]; then
    echo -n "Your RetroArch config will be reset on save and exit."
    return 0
fi

if [ "$1" == "1" ]; then
    echo -n "We recommend backing up first."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ORIGINAL_RA_FILE="/mnt/SDCARD/RetroArch/retroarch.cfg"
BACKUP_RA_FILE="/mnt/SDCARD/spruce/bin/res/retroarch.cfg"


log_message "Resetting RetroArch config to default."
cp $BACKUP_RA_FILE $ORIGINAL_RA_FILE