#!/bin/sh

# Function to delete miyoogamelist.xml files from valid directories
delete_gamelist_files() {
    rootdir="$1"

    for system in "$rootdir"/*; do
        if [ -d "$system" ]; then
            # Exclude specific directories
            case "$system" in
                *.gamelists*|*PORTS*|*FBNEO*|*MAME2003PLUS*|*ARCADE*|*NEOGEO*|*CPS1*|*CPS2*|*CPS3*|*FFPLAY*|*EASYRPG*|*MSUMD*|*SCUMMVM*|*WOLF*|*QUAKE*|*DOOM*)
                    continue
                    ;;
            esac
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

# Helper function to process games recursively
process_roms_recursive() {
    _pr_current_dir="$1"
    _pr_base_path="$2"
    _pr_imgpath="$3"
    _pr_extlist="$4"
    _pr_out="$5"
    _pr_tempfile="$6"

    # Get relative path from base
    _pr_rel_path="${_pr_current_dir#$_pr_base_path}"
    _pr_rel_path="${_pr_rel_path#/}"

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
            process_roms_recursive "$_pr_item" "$_pr_base_path" "$_pr_imgpath" "$_pr_extlist" "$_pr_out" "$_pr_tempfile"
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

            # Prefix with subdirectory for namespacing if in subdirectory
            if [ -n "$_pr_rel_path" ]; then
                _pr_digest="$_pr_rel_path/$_pr_digest"
            fi

            # Check if the cleaned name has already been used
            if grep -q "^$_pr_digest$" "$_pr_tempfile"; then
                # Use the full path without extension if it's a duplicate
                if [ -z "$_pr_rel_path" ]; then
                    _pr_name_to_use="$_pr_filename"
                else
                    _pr_name_to_use="$_pr_rel_path/$_pr_filename"
                fi
            else
                _pr_name_to_use="$_pr_digest"
                echo "$_pr_digest" >> "$_pr_tempfile"
            fi

            cat <<EOF >>$_pr_out
    <game>
        <path>$_pr_file_rel_path</path>
        <name>$_pr_name_to_use</name>
        <image>$_pr_img_rel_path</image>
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

    # Save current directory
    _orig_dir="$(pwd)"

    # Convert relative paths to absolute paths before changing directory
    case "$out" in
        /*) out_abs="$out" ;;
        *) out_abs="$_orig_dir/$out" ;;
    esac
    case "$tempfile" in
        /*) tempfile_abs="$tempfile" ;;
        *) tempfile_abs="$_orig_dir/$tempfile" ;;
    esac
    case "$tempfile_original_names" in
        /*) tempfile_original_names_abs="$tempfile_original_names" ;;
        *) tempfile_original_names_abs="$_orig_dir/$tempfile_original_names" ;;
    esac

    cd "$rompath"

    echo '<?xml version="1.0"?>' >"$out_abs"
    echo '<gameList>' >>"$out_abs"

    > "$tempfile_abs"
    > "$tempfile_original_names_abs"

    # Process ROMs recursively (use . since we're already in rompath)
    _current_abs_path="$(pwd)"
    process_roms_recursive "$_current_abs_path" "$_current_abs_path" "$imgpath" "$extlist" "$out_abs" "$tempfile_abs"

    echo '</gameList>' >>"$out_abs"
    rm -f "$tempfile_abs"
    rm -f "$tempfile_original_names_abs"

    # Return to original directory
    cd "$_orig_dir"
}
