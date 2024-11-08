#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

cores_online 4
display -t "Packing themes into 7z archives.........." -c dbcda7
echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger &

# Pack themes into 7z archives
for dir in "$THEME_DIR"/*; do
    if [ -d "$dir" ] && [ "$(basename "$dir")" != "SPRUCE" ]; then
        theme_name=$(basename "$dir")
        display -t "Packing theme: $theme_name" -c dbcda7
        7zr a -r "$THEME_DIR/$theme_name.7z" "$dir" -spf
        if [ $? -eq 0 ]; then
            rm -rf "$dir"
            display -t "Packed and removed: $theme_name" -c dbcda7 -d 1
        else
            display -t "Failed to pack: $theme_name" -c dbcda7 
        fi
    fi
done

# Backup RetroArch theme folders
RA_FOLDERS_TO_BACKUP="xmb"

for folder in $RA_FOLDERS_TO_BACKUP; do
    if [ -d "$RA_THEME_DIR/$folder" ]; then
        display -t "Packing RetroArch folder: $folder" -c dbcda7
        7zr a -r "$RA_THEME_DIR/${folder}.7z" "$RA_THEME_DIR/$folder" -spf
        if [ $? -eq 0 ]; then
            rm -rf "$RA_THEME_DIR/$folder"
            display -t "Packed and removed RetroArch folder: $folder" -c dbcda7 -d 1
        else
            display -t "Failed to pack RetroArch folder: $folder" -c dbcda7 
        fi
    else
        display -t "RetroArch folder not found: $folder" -c dbcda7 
    fi
done

log_message "Theme Packer finished running"
cores_online