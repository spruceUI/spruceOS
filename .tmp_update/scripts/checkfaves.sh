#!/bin/sh

FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
DUPLICATE_FILE="/mnt/SDCARD/Roms/favourite.duplicate"
PREVIOUS_STATE="/mnt/SDCARD/Roms/favourite.previous"
TEMP_FILE="/mnt/SDCARD/Roms/favourite_temp.json"
IMAGE_PATH="/mnt/SDCARD/.tmp_update/res/duplicategame.png"

create_duplicate() {
    cp "$FAVOURITE_FILE" "$DUPLICATE_FILE"
}

remove_duplicates() {
    awk -F'"rompath":' '
    {
        if (NF > 1) {
            split($2, arr, ",")
            split(arr[1], path, "\"")
            filename = path[2]
            
            split(filename, path_parts, "/")
            emulator_path = path_parts[4]
            split(path_parts[length(path_parts)], name_parts, ".")
            base_name = name_parts[1]
            
            if (!seen[emulator_path base_name]++) {
                print $0
            }
        }
    }
' "$DUPLICATE_FILE" > "$TEMP_FILE"

    if ! cmp -s "$DUPLICATE_FILE" "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$DUPLICATE_FILE"
        chmod 444 "$DUPLICATE_FILE"

        if [ -f "$IMAGE_PATH" ]; then
            killall -9 show
            show "$IMAGE_PATH" &
            sleep 5
        fi
    else
        rm -f "$TEMP_FILE"
    fi
}

monitor_favourite_file() {
    while true; do
        if [ -f "$FAVOURITE_FILE" ]; then
            create_duplicate

            if [ -f "$PREVIOUS_STATE" ]; then
                if ! cmp -s "$FAVOURITE_FILE" "$PREVIOUS_STATE"; then
                    remove_duplicates
                    cp "$DUPLICATE_FILE" "$FAVOURITE_FILE"
                    cp "$FAVOURITE_FILE" "$PREVIOUS_STATE"
                fi
            else
                cp "$FAVOURITE_FILE" "$PREVIOUS_STATE"
            fi
        fi
        sleep 1
    done
}

monitor_favourite_file &