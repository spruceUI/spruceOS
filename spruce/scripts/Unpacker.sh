#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"
ARCHIVE_DIR="/mnt/SDCARD/spruce/archives"

ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Check for --silent flag
SILENT_MODE=0
if [ "$1" = "--silent" ]; then
    SILENT_MODE=1
fi

# Quick check for .7z files
if [ -z "$(find "$ARCHIVE_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ] && [ -z "$(find "$THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ] && [ -z "$(find "$RA_THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ]; then
    log_message "Unpacker: No .7z files found to unpack. Exiting."
    exit 0
fi

log_message "Unpacker: Starting theme and archive unpacking process"

# Function to display text if not in silent mode
display_if_not_silent() {
    if [ $SILENT_MODE -eq 0 ]; then
        display "$@"
    fi
}

flag_add "themes_unpacking"
# Unpack themes from 7z archives
for archive in "$THEME_DIR"/*.7z; do
    if [ -f "$archive" ]; then
        theme_name=$(basename "$archive" .7z)
        display_if_not_silent --icon "$ICON" -t "$theme_name packed theme detected. Unpacking.........."
        if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
            7zr x -aoa "$archive" -o/
            if [ $? -eq 0 ]; then
                rm -f "$archive"
                log_message "Unpacker: Unpacked and removed: $theme_name.7z"
            else
                log_message "Unpacker: Failed to unpack: $theme_name.7z"
            fi
        else
            log_message "Unpacker: Skipped unpacking: $theme_name.7z (incorrect folder structure)"
        fi
    fi
done
flag_remove "themes_unpacking"

# Unpack RetroArch theme folders
RA_FOLDERS_TO_UNPACK="xmb"

flag_add "ra_themes_unpacking"
for folder in $RA_FOLDERS_TO_UNPACK; do
    archive="$RA_THEME_DIR/${folder}.7z"
    if [ -f "$archive" ]; then
        display_if_not_silent --icon "$ICON" -t "$folder packed retroarch theme detected. Unpacking.........."
        if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
            7zr x -aoa "$archive" -o/
            if [ $? -eq 0 ]; then
                rm -f "$archive"
                    log_message "Unpacker: Unpacked and removed RetroArch folder: ${folder}.7z"
            else
                log_message "Unpacker: Failed to unpack RetroArch folder: ${folder}.7z"
            fi
        else
            log_message "Unpacker: Skipped unpacking RetroArch folder: ${folder}.7z (incorrect folder structure)"
        fi
    fi
done
flag_remove "ra_themes_unpacking"

flag_add "archives_unpacking"
for archive in "$ARCHIVE_DIR"/*.7z; do
    if [ -f "$archive" ]; then
        archive_name=$(basename "$archive" .7z)
        display_if_not_silent --icon "$ICON" -t "$archive_name archive detected. Unpacking.........."
        if 7zr l "$archive" | grep -q "/mnt/SDCARD/"; then
            7zr x -aoa "$archive" -o/
            if [ $? -eq 0 ]; then
                rm -f "$archive"
                log_message "Unpacker: Unpacked and removed: $archive_name.7z"
            else
                log_message "Unpacker: Failed to unpack: $archive_name.7z"
            fi
        else
            log_message "Unpacker: Skipped unpacking: $archive_name.7z (incorrect folder structure)"
        fi
    fi
done
flag_remove "archives_unpacking"

log_message "Unpacker: Finished running"
