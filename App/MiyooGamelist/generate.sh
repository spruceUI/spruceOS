#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. "$(dirname "$0")/functions.sh"

IMAGE_PATH="/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"

echo "========================================"
echo "MiyooGamelist Generator"
echo "========================================"
echo ""

display --icon "$IMAGE_PATH" -t "Generating miyoogamelist.xml files... Please be patient, this can take a few minutes especially with large rom sets."

# Delete miyoogamelist.xml files first
delete_gamelist_files "/mnt/SDCARD/Roms"
echo ""

# Then delete cache files
delete_cache_files "/mnt/SDCARD/Roms"
echo ""

rootdir="/mnt/SDCARD/Emu"
out='miyoogamelist.xml'
tempfile='used_names.txt'
tempfile_original_names='original_names.txt'

excluded_list="PORTS|FBNEO|MAME2003PLUS|ARCADE|NEOGEO|CPS1|CPS2|CPS3|FFPLAY|EASYRPG|MSUMD|SCUMMVM|WOLF|QUAKE|DOOM"
VALID_SUBFOLDERS_PATTERN="^Imgs$|^\."

echo "Processing emulator systems..."
echo ""

_system_count=0
_processed_count=0

for system in "$rootdir"/*; do
    if [ -d "$system" ]; then
        _system_count=$((_system_count + 1))
        _system_name=$(basename "$system")

        # Check if system should be excluded using case statement
        case "$system" in
            *PORTS*|*FBNEO*|*MAME2003PLUS*|*ARCADE*|*NEOGEO*|*CPS1*|*CPS2*|*CPS3*|*FFPLAY*|*EASYRPG*|*MSUMD*|*SCUMMVM*|*WOLF*|*QUAKE*|*DOOM*)
                echo "[$_system_count] Skipping excluded system: $_system_name"
                continue
                ;;
        esac

        echo "[$_system_count] Processing system: $_system_name"
        cd "$system"

        if [ ! -f config.json ]; then
            echo "  Warning: config.json not found, skipping"
            echo ""
            continue
        fi

        rompath=$(grep -m 1 -o '"rompath": *"[^"]*"' config.json | sed -e 's/.*"rompath": *"\(.*\)"/\1/')
        extlist=$(grep -m 1 -o '"extlist": *"[^"]*"' config.json | sed -e 's/.*"extlist": *"\(.*\)"/\1/')
        imgpath=$(grep -m 1 -o '"imgpath": *"[^"]*"' config.json | sed -e 's/.*"imgpath": *"\(.*\)"/\1/')
        imgpath=".${imgpath#$rompath}"

        rompath="/mnt/SDCARD/Roms/$_system_name"
        imgpath="/mnt/SDCARD/Roms/$_system_name/Imgs"

        echo "  ROM path: $rompath"
        echo "  Extensions: $extlist"

        generate_miyoogamelist "$rompath" "$imgpath" "$extlist"
        _processed_count=$((_processed_count + 1))
        echo ""
    fi
done

echo "========================================"
echo "Summary:"
echo "  Systems checked: $_system_count"
echo "  Gamelists generated: $_processed_count"
echo "========================================"
echo "Done!"

display_kill

auto_regen_tmp_update
