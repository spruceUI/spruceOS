#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

OLD_DIR="/mnt/SDCARD/Roms/FFPLAY"
NEW_DIR="/mnt/SDCARD/Roms/VIDEOS"

if [ -d "$OLD_DIR" ]; then
    mkdir -p "$NEW_DIR"
    find "$OLD_DIR" -mindepth 1 -exec mv -t "$NEW_DIR" {} +
    log_message "$OLD_DIR folder found, moved contents of $OLD_DIR to $NEW_DIR"
    rmdir "$OLD_DIR"
fi


