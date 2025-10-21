#!/bin/sh

# Function to delete miyoogamelist.xml files from valid directories
delete_gamelist_files() {
    rootdir="$1"

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

# Function to delete cache files
delete_cache_files() {
    rootdir="$1"
    find "$rootdir" -name "*cache6.db" -exec rm {} \;
}

# Function to clean ROM names
clean_name() {
    name="$1"
    extlist="$2"

    while echo "$name" | grep -qE "\.($extlist)$"; do
        name="${name%.*}"
    done

    name=$(echo "$name" | sed -e 's/([^)]*)//g')
    name=$(echo "$name" | sed -e 's/\[[^]]*\]//g')
    name=$(echo "$name" | sed -e 's/^[0-9]\+\.//')
    name=$(echo "$name" | sed -e 's/_/ /g')
    name=$(echo "$name" | awk '{$1=$1};1')

    article=$(echo "$name" | sed -ne 's/.*, \(A\|The\|An\).*/\1/p')
    if [ ! -z "$article" ]; then
        name="$article $(echo "$name" | sed -e 's/, \(A\|The\|An\)//')"
    fi

    name=$(echo "$name" | sed -e 's/ - /: /')

    echo "$name"
}

# Helper function to process games recursively
process_roms_recursive() {
    local current_dir="$1"
    local base_path="$2"
    local imgpath="$3"
    local extlist="$4"
    local out="$5"
    local tempfile="$6"

    # Get relative path from base
    local rel_path="${current_dir#$base_path}"
    rel_path="${rel_path#/}"

    # Process files in current directory
    for item in "$current_dir"/*; do
        if [ ! -e "$item" ]; then
            continue
        fi

        local item_name=$(basename "$item")

        if [ -d "$item" ]; then
            # Skip Imgs directory and hidden directories
            if [ "$item_name" = "Imgs" ] || echo "$item_name" | grep -q "^\."; then
                continue
            fi
            # Recursively process subdirectory
            process_roms_recursive "$item" "$base_path" "$imgpath" "$extlist" "$out" "$tempfile"
        elif echo "$item_name" | grep -qE "\.($extlist)$"; then
            # Process ROM file
            local filename="${item_name%.*}"

            # Build relative path from rompath
            if [ -z "$rel_path" ]; then
                local file_rel_path="./$item_name"
                local img_rel_path="$imgpath/$filename.png"
            else
                local file_rel_path="./$rel_path/$item_name"
                local img_rel_path="$imgpath/$rel_path/$filename.png"
            fi

            # Clean the name for display
            local digest=$(clean_name "$item_name" "$extlist")

            # Prefix with subdirectory for namespacing if in subdirectory
            if [ ! -z "$rel_path" ]; then
                digest="$rel_path/$digest"
            fi

            # Check if the cleaned name has already been used
            local name_to_use
            if grep -q "^$digest$" "$tempfile"; then
                # Use the full path without extension if it's a duplicate
                if [ -z "$rel_path" ]; then
                    name_to_use="$filename"
                else
                    name_to_use="$rel_path/$filename"
                fi
            else
                name_to_use="$digest"
                echo "$digest" >> "$tempfile"
            fi

            cat <<EOF >>$out
    <game>
        <path>$file_rel_path</path>
        <name>$name_to_use</name>
        <image>$img_rel_path</image>
    </game>
EOF
        fi
    done
}

# Function to generate miyoogamelist.xml
generate_miyoogamelist() {
    rompath=$1
    imgpath=$2
    extlist=$3
    out=${4:-miyoogamelist.xml}
    tempfile=${5:-used_names.txt}
    tempfile_original_names=${6:-original_names.txt}

    cd "$rompath"

    echo '<?xml version="1.0"?>' >$out
    echo '<gameList>' >>$out

    > "$tempfile"
    > "$tempfile_original_names"

    # Process ROMs recursively
    process_roms_recursive "$rompath" "$rompath" "$imgpath" "$extlist" "$out" "$tempfile"

    echo '</gameList>' >>$out
    rm "$tempfile"
    rm "$tempfile_original_names"
}
