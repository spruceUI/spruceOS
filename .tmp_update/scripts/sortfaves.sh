#!/bin/sh

FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
DUPLICATE_FILE="/mnt/SDCARD/Roms/favourite.duplicate"
PREVIOUS_STATE="/mnt/SDCARD/Roms/favourite.previous"
TEMP_FILE="/mnt/SDCARD/Roms/favourite_temp.json"

sort_file() {
    local FILE=$1
    local TEMP=$2

    if [ ! -f "$FILE" ]; then
        return 1
    fi

    awk -F'"label":' '
        {
            if (NF > 1) {
                split($2, arr, ",")
                split(arr[1], label, "\"")
                print $0
            }
        }
    ' "$FILE" | sort -t'"' -k4,4 > "$TEMP"

    {
        echo "[]"
        awk '{print}' "$TEMP"
    } > "$FILE"

    rm "$TEMP"
    return 0
}

sort_file "$FAVOURITE_FILE" "$TEMP_FILE"
sort_file "$DUPLICATE_FILE" "$TEMP_FILE"
sort_file "$PREVIOUS_STATE" "$TEMP_FILE"
