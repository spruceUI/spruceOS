#!/bin/sh

# Function to delete miyoogamelist.xml files from valid directories
delete_gamelist_files() {
    rootdir="$1"

    echo "Deleting existing miyoogamelist.xml files..."
    for system in "$rootdir"/*; do
        if [ -d "$system" ]; then
            # Exclude specific directories
            case "$system" in
                *.gamelists*|*PORTS*|*FBNEO*|*MAME2003PLUS*|*ARCADE*|*NEOGEO*|*CPS1*|*CPS2*|*CPS3*|*FFPLAY*|*EASYRPG*|*MSUMD*|*SCUMMVM*|*WOLF*|*QUAKE*|*DOOM*)
                    continue
                    ;;
            esac
            # Find and delete miyoogamelist.xml files in non-excluded directories
            _system_name=$(basename "$system")
            _count=$(find "$system" -name "miyoogamelist.xml" | wc -l)
            if [ $_count -gt 0 ]; then
                echo "  Removing $_count file(s) from $_system_name"
                find "$system" -name "miyoogamelist.xml" -exec rm {} +
            fi
        fi
    done
    echo "Done deleting miyoogamelist.xml files"
}

# Function to delete cache files
delete_cache_files() {
    rootdir="$1"
    echo "Deleting cache files..."
    _cache_count=$(find "$rootdir" -name "*cache6.db" | wc -l)
    if [ $_cache_count -gt 0 ]; then
        echo "  Removing $_cache_count cache file(s)"
        find "$rootdir" -name "*cache6.db" -exec rm {} \;
    else
        echo "  No cache files found"
    fi
    echo "Done deleting cache files"
}

# Function to clean ROM names
clean_name() {
    name="$1"
    extlist="$2"

    # Strip extensions - convert extlist to case pattern
    _cn_has_ext=1
    while [ $_cn_has_ext -eq 1 ]; do
        _cn_has_ext=0
        _cn_old_name="$name"
        # Check each extension in the list
        _cn_ifs_save="$IFS"
        IFS="|"
        for _cn_ext in $extlist; do
            case "$name" in
                *.$_cn_ext)
                    name="${name%.*}"
                    _cn_has_ext=1
                    break
                    ;;
            esac
        done
        IFS="$_cn_ifs_save"
        # Safety check to prevent infinite loop
        if [ "$name" = "$_cn_old_name" ]; then
            break
        fi
    done

    name=$(echo "$name" | sed -e 's/([^)]*)//g')
    name=$(echo "$name" | sed -e 's/\[[^]]*\]//g')
    name=$(echo "$name" | sed -e 's/^[0-9]\+\.//')
    name=$(echo "$name" | sed -e 's/_/ /g')
    name=$(echo "$name" | awk '{$1=$1};1')

    article=$(echo "$name" | sed -ne 's/.*, \(A\|The\|An\).*/\1/p')
    if [ -n "$article" ]; then
        name="$article $(echo "$name" | sed -e 's/, \(A\|The\|An\)//')"
    fi

    name=$(echo "$name" | sed -e 's/ - /: /')

    echo "$name"
}

# Sanitize a string for safe inclusion in XML (remove invalid chars and escape specials)
sanitize_xml() {
    _sx_input="$1"
    _sx_clean=$(printf '%s' "$_sx_input" | tr -d '\000-\010\013\014\016-\037')
    _sx_clean=$(printf '%s' "$_sx_clean" \
        | sed -e 's/&/\&amp;/g' \
              -e 's/</\&lt;/g' \
              -e 's/>/\&gt;/g' \
              -e 's/"/\&quot;/g' \
              -e "s/'/\&apos;/g")
    echo "$_sx_clean"
}

# Helper function to process games recursively
process_roms_recursive() {
    _pr_current_dir="$1"
    _pr_base_path="$2"
    _pr_imgpath="$3"
    _pr_extlist="$4"
    _pr_out="$5"

    # Get relative path from base
    _pr_rel_path="${_pr_current_dir#$_pr_base_path}"
    _pr_rel_path="${_pr_rel_path#/}"

    # Show directory being processed
    if [ -n "$_pr_rel_path" ]; then
        echo "  Scanning subdirectory: $_pr_rel_path"
    fi

    # Process files in current directory
    for _pr_item in "$_pr_current_dir"/*; do
        if [ ! -e "$_pr_item" ]; then
            continue
        fi

        _pr_item_name=$(basename "$_pr_item")

        if [ -d "$_pr_item" ]; then
            # Skip Imgs directory and hidden directories
            if [ "$_pr_item_name" = "Imgs" ] || echo "$_pr_item_name" | grep -q "^\."; then
                continue
            fi
            # Recursively process subdirectory
            process_roms_recursive "$_pr_item" "$_pr_base_path" "$_pr_imgpath" "$_pr_extlist" "$_pr_out"
        else
            # Check if file matches any extension
            _pr_match=0
            _pr_ifs_save="$IFS"
            IFS="|"
            for _pr_ext in $_pr_extlist; do
                case "$_pr_item_name" in
                    *.$_pr_ext)
                        _pr_match=1
                        break
                        ;;
                esac
            done
            IFS="$_pr_ifs_save"

            if [ $_pr_match -eq 0 ]; then
                continue
            fi
            # Process ROM file
            _pr_filename="${_pr_item_name%.*}"

            # Build relative path from rompath
            if [ -z "$_pr_rel_path" ]; then
                _pr_file_rel_path="./$_pr_item_name"
                _pr_img_rel_path="$_pr_imgpath/$_pr_filename.png"
            else
                _pr_file_rel_path="./$_pr_rel_path/$_pr_item_name"
                _pr_img_rel_path="$_pr_imgpath/$_pr_rel_path/$_pr_filename.png"
            fi

            # Clean the name for display
            _pr_digest=$(clean_name "$_pr_item_name" "$_pr_extlist")

            _pr_name_to_use="$_pr_digest"

            # Sanitize values before writing XML
            _pr_file_rel_path_xml=$(sanitize_xml "$_pr_file_rel_path")
            _pr_name_to_use_xml=$(sanitize_xml "$_pr_name_to_use")
            _pr_img_rel_path_xml=$(sanitize_xml "$_pr_img_rel_path")

            cat <<EOF >>$_pr_out
    <game>
        <path>$_pr_file_rel_path_xml</path>
        <name>$_pr_name_to_use_xml</name>
        <image>$_pr_img_rel_path_xml</image>
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

    echo "Generating $out..."
    echo '<?xml version="1.0"?>' >$out
    echo '<gameList>' >>$out

    > "$tempfile"
    > "$tempfile_original_names"

    # Process ROMs recursively
    process_roms_recursive "$rompath" "$rompath" "$imgpath" "$extlist" "$out" "$tempfile"

    _game_count=$(grep -c '<game>' "$out")
    echo "  Found $_game_count game(s)"

    echo '</gameList>' >>$out
    rm "$tempfile"
    rm "$tempfile_original_names"
    echo "  Saved to: $rompath/$out"
}
