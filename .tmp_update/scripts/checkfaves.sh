#!/bin/sh

FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
DUPLICATE_FILE="/mnt/SDCARD/Roms/favourite.duplicate"
PREVIOUS_STATE="/mnt/SDCARD/Roms/favourite.previous"
TEMP_FILE="/mnt/SDCARD/Roms/favourite_temp.json"
IMAGE_PATH="/mnt/SDCARD/.tmp_update/res/duplicategame.png"

create_duplicate() {
    cp "$FAVOURITE_FILE" "$DUPLICATE_FILE"
}

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

remove_duplicates() {
    sort_file "$DUPLICATE_FILE" "$TEMP_FILE"
    {
        awk -v launch='launch' -v rompath='rompath' '{ 
            line = $0
            split("", kv)
            nelems = split(line, elems, ",")
            for(i=1; i<=nelems; i++){
                elem=elems[i]
                cnt = 0
                while ( match(elem,/"[^"]*"/) ) {
                hit = substr(elem,RSTART+1,RLENGTH-2)
                if ( ++cnt % 2 ) {
                    tag = hit
                }
                else {
                    val = hit
                    kv[tag] = val
                }
                elem = substr(elem,RSTART+RLENGTH)
                }
            }
            npath = split(kv[launch], path_parts, "/")
            app = path_parts[npath-1]
            
            nrom = split(kv[rompath], rom_parts, "/")
            rom = rom_parts[nrom]
            romfolder = rom_parts[nrom-1]
            if (!seen[app rom romfolder]++) {
                print $0
            }
        }' "$DUPLICATE_FILE" 
    } > "$TEMP_FILE"

    if ! cmp -s "$DUPLICATE_FILE" "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$DUPLICATE_FILE"
        chmod 444 "$DUPLICATE_FILE"

        if [ -f "$IMAGE_PATH" ]; then
            killall -9 show
            show "$IMAGE_PATH" &
            sleep 5
            killall -9 show
        fi
    else
        rm -f "$TEMP_FILE"
    fi
}

monitor_favourite_file() {
    while true; do
        if [ -f "$FAVOURITE_FILE" ]; then
            /mnt/SDCARD/.tmp_update/bin/inotify.elf $FAVOURITE_FILE
            if [ -f "$PREVIOUS_STATE" ]; then
                if ! cmp -s "$FAVOURITE_FILE" "$PREVIOUS_STATE"; then
                    create_duplicate
                    remove_duplicates
                    cp "$DUPLICATE_FILE" "$FAVOURITE_FILE"
                    cp "$FAVOURITE_FILE" "$PREVIOUS_STATE"
                fi
            else
                cp "$FAVOURITE_FILE" "$PREVIOUS_STATE"
            fi
        else
            touch $FAVOURITE_FILE
        fi 
    done
}

monitor_favourite_file &