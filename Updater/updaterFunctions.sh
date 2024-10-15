boost_processing(){
    /mnt/SDCARD/App/utils/utils "performance" 4 1344 384 1080 1	
	echo "CPU Mode set to PERFORMANCE"
    echo 1 >/sys/devices/system/cpu/cpu0/online
    echo 1 >/sys/devices/system/cpu/cpu1/online
    echo 1 >/sys/devices/system/cpu/cpu2/online
    echo 1 >/sys/devices/system/cpu/cpu3/online
}

check_for_update_file() {
    echo "Searching for update file"
    UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)
    echo "Found update file: $UPDATE_FILE"

    if [ -z "$UPDATE_FILE" ]; then
        echo "No update file found"
        return 1
    fi
    return 0
}


verify_7z_content() {
    local archive="$1"
    local required_dirs="App Emu"
    local missing_dirs=""

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Verifying update file contents"
    
    # List contents of the archive and save to a temporary file
    local temp_list=$(mktemp)
    7zr l "$archive" > "$temp_list"
    
    # Uncomment both lines to debug archive contents
    #echo "$(date '+%Y-%m-%d %H:%M:%S') - Debug: Archive contents:"
    #cat "$temp_list"
    
    for dir in $required_dirs; do
        if ! grep -q "^[0-9-]* [0-9:]* D\.\.\.\. *0 *0 *$dir$" "$temp_list"; then
            missing_dirs="$missing_dirs $dir"
        fi
    done
    
    rm -f "$temp_list"

    if [ -n "$missing_dirs" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Required director(ies)$missing_dirs not found in 7z file"
        return 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - All required directories found in 7z file"
    return 0
}
