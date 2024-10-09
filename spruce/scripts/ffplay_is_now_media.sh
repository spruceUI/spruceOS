#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

OLD_DIR="/mnt/SDCARD/Roms/FFPLAY"
NEW_DIR="/mnt/SDCARD/Roms/MEDIA"

if [ -d "$OLD_DIR" ]; then
    mv "$OLD_DIR"/* "$NEW_DIR"/
    rmdir “$OLD_DIR”
    log_message "Found $OLD_DIR folder; moved contents of $OLD_DIR to $NEW_DIR"
fi