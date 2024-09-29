#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"
ROOT_DIR="/mnt/SDCARD"

. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh

cores_online 4
log_message "Starting theme unpacking process"

# Unpack themes from 7z archives
for archive in "$THEME_DIR"/*.7z; do
    if [ -f "$archive" ]; then
        theme_name=$(basename "$archive" .7z)
        display_text -i "/mnt/SDCARD/spruce/imgs/displayTextPreColor.png" -t "$theme_name packed theme detected. Unpacking.........." -c dbcda7
        if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
            7zr x "$archive" -o/
            if [ $? -eq 0 ]; then
                rm -f "$archive"
                log_message "Unpacked and removed: $theme_name.7z"
            else
                log_message "Failed to unpack: $theme_name.7z"
            fi
        else
            log_message "Skipped unpacking: $theme_name.7z (incorrect folder structure)"
        fi
    fi
done

# Unpack RetroArch theme folders
RA_FOLDERS_TO_UNPACK="xmb"

for folder in $RA_FOLDERS_TO_UNPACK; do
    archive="$RA_THEME_DIR/${folder}.7z"
    if [ -f "$archive" ]; then
        if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
            7zr x "$archive" -o/
            if [ $? -eq 0 ]; then
                rm -f "$archive"
                log_message "Unpacked and removed RetroArch folder: ${folder}.7z"
            else
                log_message "Failed to unpack RetroArch folder: ${folder}.7z"
            fi
        else
            log_message "Skipped unpacking RetroArch folder: ${folder}.7z (incorrect folder structure)"
        fi
    else
        log_message "RetroArch archive not found: ${folder}.7z"
    fi
done

log_message "Theme Unpacker finished running"
kill_images
cores_online
