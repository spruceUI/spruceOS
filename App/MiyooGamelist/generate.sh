#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/Themes/SPRUCE/icons/app/gamelist.png"

display --icon "$IMAGE_PATH" -t "Generating miyoogamelist.xml files... Please be patient, as this can take a few minutes."

delete_gamelist_files() {
    rootdir="/mnt/SDCARD/roms"
    
    for system in "$rootdir"/*; do
        if [ -d "$system" ]; then
            # Exclude specific directories
            if echo "$system" | grep -qE "(.gamelists|PORTS|FBNEO|MAME2003PLUS|ARCADE|NEOGEO|CPS1|CPS2|CPS3|FFPLAY|EASYRPG|MSUMD|SCUMMVM|WOLF|QUAKE|DOOM)"; then
                continue
            fi
            # Find and delete miyoogamelist.xml files in non-excluded directories
            find "$system" -name "miyoogamelist.xml" -exec rm {} +
        fi
    done
}

delete_cache_files() {
    find /mnt/SDCARD/roms -name "*cache6.db" -exec rm {} \;
}

# Delete miyoogamelist.xml files first
delete_gamelist_files

# Then delete cache files
delete_cache_files

rootdir="/mnt/SDCARD/Emu"
out='miyoogamelist.xml'
tempfile='used_names.txt'
tempfile_original_names='original_names.txt'

excluded_list="PORTS|FBNEO|MAME2003PLUS|ARCADE|NEOGEO|CPS1|CPS2|CPS3|FFPLAY|EASYRPG|MSUMD|SCUMMVM|WOLF|QUAKE|DOOM"
VALID_SUBFOLDERS_PATTERN="^Imgs$|^\."

clean_name() {
    name="$1"
    extlist="$2"

    while echo "$name" | grep -qE "\.($extlist)$"; do
        name="${name%.*}"
    done

    name=$(echo "$name" | sed -e 's/([^)]*)//g')
    name=$(echo "$name" | sed -e 's/\[[^]]*\]//g')
    name=$(echo "$name" | sed -e 's/^[0-9]\+\.//')
    name=$(echo "$name" | awk '{$1=$1};1')

    article=$(echo "$name" | sed -ne 's/.*, \(A\|The\|An\).*/\1/p')
    if [ ! -z "$article" ]; then
        name="$article $(echo "$name" | sed -e 's/, \(A\|The\|An\)//')"
    fi

    name=$(echo "$name" | sed -e 's/ - /: /')

    echo "$name"
}

generate_miyoogamelist() {
    rompath=$1
    imgpath=$2
    extlist=$3

    cd "$rompath"

    echo '<?xml version="1.0"?>' >$out
    echo '<gameList>' >>$out

    > "$tempfile"
    > "$tempfile_original_names"

    for rom in *; do
        if [ -d "$rom" ]; then
            continue
        fi

        if ! echo "$rom" | grep -qE "\.($extlist)$"; then
            continue
        fi

        filename="${rom%.*}"  # Filename without extension
        original_name=$(basename "$rom")  # Original name with extension
        digest=$(clean_name "$rom" "$extlist")

        # Check if the cleaned name has already been used
        if grep -q "^$digest$" "$tempfile"; then
            # Use the original name if it's a duplicate
            name_to_use="$filename"
        else
            name_to_use="$digest"
            echo "$digest" >> "$tempfile"
        fi

        cat <<EOF >>$out
    <game>
        <path>./$rom</path>
        <name>$name_to_use</name>
        <image>$imgpath/$filename.png</image>
    </game>
EOF

        echo "$original_name" >> "$tempfile_original_names"
    done

    echo '</gameList>' >>$out
    rm "$tempfile"
    rm "$tempfile_original_names"
}

for system in "$rootdir"/*; do
    if [ -d "$system" ]; then
        if echo "$system" | grep -qE "$excluded_list"; then
            continue
        fi

        cd "$system"

        rompath=$(grep -E '"rompath":' config.json | sed -e 's/^.*:\s*"\(.*\)",*/\1/')
        extlist=$(grep -E '"extlist":' config.json | sed -e 's/^.*:\s*"\(.*\)",*/\1/')
        imgpath=$(grep -E '"imgpath":' config.json | sed -e 's/^.*:\s*"\(.*\)",*/\1/')
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