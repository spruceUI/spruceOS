#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. "$(dirname "$0")/functions.sh"

IMAGE_PATH="/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"

display --icon "$IMAGE_PATH" -t "Generating miyoogamelist.xml files... Please be patient, as this can take a few minutes."

# Delete miyoogamelist.xml files first
delete_gamelist_files "/mnt/SDCARD/Roms"

# Then delete cache files
delete_cache_files "/mnt/SDCARD/Roms"

rootdir="/mnt/SDCARD/Emu"
out='miyoogamelist.xml'
tempfile='used_names.txt'
tempfile_original_names='original_names.txt'

excluded_list="PORTS|FBNEO|MAME2003PLUS|ARCADE|NEOGEO|CPS1|CPS2|CPS3|FFPLAY|EASYRPG|MSUMD|SCUMMVM|WOLF|QUAKE|DOOM"
VALID_SUBFOLDERS_PATTERN="^Imgs$|^\."

for system in "$rootdir"/*; do
    if [ -d "$system" ]; then
        if echo "$system" | grep -qE "$excluded_list"; then
            continue
        fi

        cd "$system"

        rompath=$(grep -m 1 -oE '"rompath": *"[^"]+"' config.json | sed -E 's/.*"rompath": *"(.*)"/\1/')
        extlist=$(grep -m 1 -oE '"extlist": *"[^"]+"' config.json | sed -E 's/.*"extlist": *"(.*)"/\1/')
        imgpath=$(grep -m 1 -oE '"imgpath": *"[^"]+"' config.json | sed -E 's/.*"imgpath": *"(.*)"/\1/')
        imgpath=".${imgpath#$rompath}"

        valid_subfolders=true
        for folder in "$rompath"/*/; do
            folder_name=$(basename "$folder")
            echo "$folder_name" | grep -E "$VALID_SUBFOLDERS_PATTERN" > /dev/null
            if [ $? -ne 0 ]; then
                valid_subfolders=false
                break
            fi
        done

        if [ "$valid_subfolders" = false ]; then
            if [ -f "$out" ]; then
                rm "$out"
            fi
            continue
        fi

        generate_miyoogamelist "$rompath" "$imgpath" "$extlist"
    fi
done

display_kill

auto_regen_tmp_update
