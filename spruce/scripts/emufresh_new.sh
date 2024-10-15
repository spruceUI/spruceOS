#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

EMU_DIR="/mnt/SDCARD/Emu"
ROM_DIR="/mnt/SDCARD/Roms"

##### DEFINE FUNCTIONS #####

delete_cache_files() {
    find $ROM_DIR -name "*cache6.db" -exec rm {} \;
}

is_hidden() {
    json_file="$1/config.json"
    [ -f "$json_file" ] && grep -q '"#label"' "$json_file" && echo "true" || echo "false"
}

has_roms() {
    system_name="$(basename "$1")"
    search_dir="$ROM_DIR/$system_name"
    json_file="$1/config.json"

    # Check if config.json exists
    if [ ! -f "$json_file" ]; then
        echo "false"
        return
    fi

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

hide_system() {
    if [ "$(is_hidden "$1")" = "false" ]; then
        sed -i 's|"label:"|"\#label"|' "$1/config.json"
    fi
}

unhide_system() {
    if [ "$(is_hidden "$1")" = "true" ]; then
        sed -i 's|"\#label:"|"label"|' "$1/config.json"
    fi
}


##### MAIN EXECUTION #####

delete_cache_files

for dir in "$EMU_DIR"/*; do
    if [ -d "$dir" ]; then
        if has_roms "$dir"; then
            unhide_system "$dir"
        else
            hide_system "$dir"
        fi
    fi
done

P8_DIR="${EMU_DIR}/PICO8"
if [ -f "$P8_DIR/bin/pico8.dat" ] && [ -f "$P8_DIR/bin/pico8_dyn" ]; then
    unhide_system "$P8_DIR"
else
    hide_system "$P8_DIR"
fi