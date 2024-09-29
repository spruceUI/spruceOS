#!/bin/sh

THEME_DIR="/mnt/SDCARD/Themes"
RA_THEME_DIR="/mnt/SDCARD/RetroArch/.retroarch/assets"

. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh

cores_online 4
display_text -t "Packing themes into 7z archives.........." -c dbcda7
echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger &

# Pack themes into 7z archives
for dir in "$THEME_DIR"/*; do
    if [ -d "$dir" ] && [ "$(basename "$dir")" != "SPRUCE" ]; then
        theme_name=$(basename "$dir")
        display_text -t "Packing theme: $theme_name" -c dbcda7
        7zr a -r "$THEME_DIR/$theme_name.7z" "$dir" -spf
        if [ $? -eq 0 ]; then
            rm -rf "$dir"
            display_text -t "Packed and removed: $theme_name" -c dbcda7 -d 1
        else
            display_text -t "Failed to pack: $theme_name" -c dbcda7 
        fi
    fi
done

# Backup RetroArch theme folders
RA_FOLDERS_TO_BACKUP="xmb"

for folder in $RA_FOLDERS_TO_BACKUP; do
    if [ -d "$RA_THEME_DIR/$folder" ]; then
        display_text -t "Packing RetroArch folder: $folder" -c dbcda7
        7zr a -r "$RA_THEME_DIR/${folder}.7z" "$RA_THEME_DIR/$folder" -spf
        if [ $? -eq 0 ]; then
            rm -rf "$RA_THEME_DIR/$folder"
            display_text -t "Packed and removed RetroArch folder: $folder" -c dbcda7 -d 1
        else
            display_text -t "Failed to pack RetroArch folder: $folder" -c dbcda7 
        fi
    else
        display_text -t "RetroArch folder not found: $folder" -c dbcda7 
    fi
done

log_message "Theme Packer finished running"
kill_images
cores_online