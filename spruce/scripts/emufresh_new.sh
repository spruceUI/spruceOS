#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

EMU_DIR="/mnt/SDCARD/Emu"
ROM_DIR="/mnt/SDCARD/Roms"
JSON="config.json"


##### DEFINE FUNCTIONS #####

is_hidden() {
    if grep -q '"#label"' "$1"; then
        echo "true"
    else
        echo "false"
    fi
}

check_for_roms() {
    json_file="$1"
    search_dir="$2"

    # Extract extensions from JSON file
    extensions=$(grep -oP '"extlist": "\K[^"]+' "$json_file" | tr '|' '\n' | sed 's/^\.//')

    # Check for files with any of the extensions
    for ext in $extensions; do
        if find "$search_dir" -type f -name "*.$ext" | grep -q .; then
            echo "true"
            return
        fi
    done

    echo "false"
}





##### MAIN EXECUTION #####

for dir in "$EMU_DIR"; do

done