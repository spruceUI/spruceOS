#!/bin/sh
if [ "$1" == "0" ]; then
    echo -n "Your PPSSPP config will be reset on save and exit."
    return 0
fi

if [ "$1" == "1" ]; then
    echo -n "We recommend backing up first."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ORIGINAL_PPSSPP_FILE="/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM/ppsspp.ini"
ORIGINAL_PPSSPP_CONTROLS_FILE="/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM/controls.ini"
BACKUP_PPSSPP_FILE="/mnt/SDCARD/Emu/.emu_setup/.config/ppsspp/PSP/SYSTEM/ppsspp.ini"
BACKUP_PPSSPP_CONTROLS_FILE="/mnt/SDCARD/Emu/.emu_setup/.config/ppsspp/PSP/SYSTEM/controls.ini"


log_message "Resetting PPSSPP config to default."
cp $BACKUP_PPSSPP_FILE $ORIGINAL_PPSSPP_FILE
cp $BACKUP_PPSSPP_CONTROLS_FILE $ORIGINAL_PPSSPP_CONTROLS_FILE
