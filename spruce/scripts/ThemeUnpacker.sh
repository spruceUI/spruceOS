#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"
ROOT_DIR="/mnt/SDCARD"


ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Check for --silent flag
SILENT_MODE=0
if [ "$1" = "--silent" ]; then
    SILENT_MODE=1
fi

# Quick check for .7z files
if [ -z "$(find "$THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ] && [ -z "$(find "$RA_THEME_DIR" -maxdepth 1 -name '*.7z' | head -n 1)" ]; then
    log_message "ThemeUnpacker: No .7z files found to unpack. Exiting."
    exit 0
fi

log_message "ThemeUnpacker: Starting theme unpacking process"

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
                log_message "ThemeUnpacker: Unpacked and removed: $theme_name.7z"
            else
                log_message "ThemeUnpacker: Failed to unpack: $theme_name.7z"
            fi
        else
            log_message "ThemeUnpacker: Skipped unpacking: $theme_name.7z (incorrect folder structure)"
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
                    log_message "ThemeUnpacker: Unpacked and removed RetroArch folder: ${folder}.7z"
            else
                log_message "ThemeUnpacker: Failed to unpack RetroArch folder: ${folder}.7z"
            fi
        else
            log_message "ThemeUnpacker: Skipped unpacking RetroArch folder: ${folder}.7z (incorrect folder structure)"
        fi
    fi
done
flag_remove "ra_themes_unpacking"

log_message "ThemeUnpacker: Finished running"
