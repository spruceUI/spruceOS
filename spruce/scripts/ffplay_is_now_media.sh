#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

OLD_DIR="/mnt/SDCARD/Roms/FFPLAY"
NEW_DIR="/mnt/SDCARD/Roms/MEDIA"

if [ -d "$OLD_DIR" ]; then
    mkdir -p "$NEW_DIR"
    
    # Move all contents, including hidden files and subdirectories
    cd "$OLD_DIR" || exit 1
    find . -mindepth 1 -exec sh -c '
        for item do
            if [ -e "$item" ]; then
                dir=$(dirname "$item")
                mkdir -p "'"$NEW_DIR"'/$dir"
                mv "$item" "'"$NEW_DIR"'/$item"
            fi
        done
    ' sh {} +
    
    # Check if the move was successful
    if [ $? -eq 0 ]; then
        log_message "Contents of $OLD_DIR successfully moved to $NEW_DIR"
        cd ..
        rm -rf "$OLD_DIR"
        if [ $? -eq 0 ]; then
            log_message "$OLD_DIR folder and any remaining contents removed"
        fi
    fi
fi