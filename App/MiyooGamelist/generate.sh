#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. "$(dirname "$0")/functions.sh"

IMAGE_PATH="/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"

start_pyui_message_writer

display_image_and_text "$IMAGE_PATH" "Generating miyoogamelist.xml files...\n\nPlease be patient, as this can take a few minutes."
sleep 2

# Delete miyoogamelist.xml files first
delete_gamelist_files "/mnt/SDCARD/Roms"

# Then delete cache files
delete_cache_files "/mnt/SDCARD/Roms"

emudir="/mnt/SDCARD/Emu"
romsdir="/mnt/SDCARD/Roms"

excluded_list="PORTS|FBNEO|MAME2003PLUS|ARCADE|NEOGEO|CPS1|CPS2|CPS3|FFPLAY|EASYRPG|MSUMD|SCUMMVM|WOLF|QUAKE|DOOM"
VALID_SUBFOLDERS_PATTERN="^Imgs$|^\."

for system in "$emudir"/*; do
    if [ -d "$system" ]; then
        system_name=$(basename "$system")

        # Check if system should be excluded using case statement
        case "$system_name" in
            PORTS|FBNEO|MAME2003PLUS|ARCADE|NEOGEO|CPS1|CPS2|CPS3|FFPLAY|EASYRPG|MSUMD|SCUMMVM|WOLF|QUAKE|DOOM)
                continue
                ;;
        esac

        # Get extension list from config.json
        extlist=$(grep -m 1 -o '"extlist": *"[^"]*"' "$system/config.json" 2>/dev/null | sed -e 's/.*"extlist": *"\(.*\)"/\1/')

        # Skip if no extlist found or no config.json
        if [ -z "$extlist" ]; then
            continue
        fi

        # Set ROM path and image path
        rompath="$romsdir/$system_name"
        imgpath="./Imgs"

        # Skip if ROM directory doesn't exist
        if [ ! -d "$rompath" ]; then
            continue
        fi

        # Check for invalid subfolders (folders that are not Imgs or hidden)
        valid_subfolders=true
        for folder in "$rompath"/*/; do
            # Skip if no subdirectories exist
            if [ ! -e "$folder" ]; then
                break
            fi

            folder_name=$(basename "$folder")
            # Check if folder is Imgs or starts with .
            case "$folder_name" in
                Imgs|.*)
                    # Valid subfolder, continue
                    ;;
                *)
                    # Invalid subfolder found - ROMs are in subdirectories
                    valid_subfolders=false
                    break
                    ;;
            esac
        done

        # If there are subdirectories with ROMs, don't generate XML
        if [ "$valid_subfolders" = false ]; then
            # Remove any existing XML file for this system
            if [ -f "$rompath/miyoogamelist.xml" ]; then
                rm "$rompath/miyoogamelist.xml"
            fi
            continue
        fi

        # Generate the miyoogamelist.xml file
        out="$rompath/miyoogamelist.xml"
        tempfile="$rompath/used_names.txt"
        tempfile_original_names="$rompath/original_names.txt"

        display_image_and_text "$IMAGE_PATH" "Generating miyoogamelist.xml for $system_name..."
        generate_miyoogamelist "$rompath" "$imgpath" "$extlist" "$out" "$tempfile" "$tempfile_original_names"
    fi
done

auto_regen_tmp_update
