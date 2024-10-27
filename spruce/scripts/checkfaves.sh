#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
DUPLICATE_FILE="/mnt/SDCARD/Roms/favourite.duplicate"
PREVIOUS_STATE="/mnt/SDCARD/Roms/favourite.previous"
TEMP_FILE="/mnt/SDCARD/Roms/favourite_temp.json"
IMAGE_PATH="/mnt/SDCARD/spruce/imgs/duplicate_file.png"

create_duplicate() {
    cp "$FAVOURITE_FILE" "$DUPLICATE_FILE" && log_message "checkfaves.sh: copied $FAVOURITE_FILE into $DUPLICATE_FILE"
}

sort_file() {
    local FILE=$1
    local TEMP=$2

    if [ ! -f "$FILE" ]; then
        log_message "checkfaves.sh: $FILE does not exist, so cannot be sorted."
        return 1
    fi

    log_message "checkfaves.sh: sorting $FILE"

    awk -F'"label":' '
        {
            if (NF > 1) {
                split($2, arr, ",")
                split(arr[1], label, "\"")
                print $0
            }
        }
    ' "$FILE" | sort -t'"' -k4,4 > "$TEMP"

    log_message "checkfaves.sh: sorted $FILE into $TEMP"

    {
        echo "[]"
        awk '{print}' "$TEMP"
    } > "$FILE"
    log_message "checkfaves.sh: printed $TEMP into $FILE"

    rm "$TEMP" && log_message "checkfaves.sh: removed $TEMP"
    return 0
}

remove_duplicates() {
    sort_file "$DUPLICATE_FILE" "$TEMP_FILE"
    log_message "checkfaves.sh: removing duplicates"
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
            log_message "checkfaves.sh: displaying $IMAGE_PATH"
            display --icon "$IMAGE_PATH" -d 5 -t "You cannot add multiple games with the same exact name to Favorites. Please rename the file you wish to add, then try again."
        fi
    else
        rm -f "$TEMP_FILE"
    fi
}

monitor_favourite_file() {
    log_message "checkfaves.sh: begin monitoring favourites file"
    while true; do
        if [ -f "$FAVOURITE_FILE" ]; then
            log_message "checkfaves.sh: $FAVOURITE_FILE exists"
            inotifywait -e modify $FAVOURITE_FILE
            if [ -f "$PREVIOUS_STATE" ]; then
                log_message "checkfaves.sh: $PREVIOUS_STATE exists"
                if ! cmp -s "$FAVOURITE_FILE" "$PREVIOUS_STATE"; then
                    log_message "checkfaves.sh: $FAVOURITE_FILE and $PREVIOUS_STATE do not match"
                    create_duplicate
                    remove_duplicates
                    cp "$DUPLICATE_FILE" "$FAVOURITE_FILE" && log_message "checkfaves.sh: copied $DUPLICATE_FILE into $FAVOURITE_FILE"
                    cp "$FAVOURITE_FILE" "$PREVIOUS_STATE" && log_message "checkfaves.sh: copied $FAVOURITE_FILE into $PREVIOUS_STATE"
                fi
            else
                cp "$FAVOURITE_FILE" "$PREVIOUS_STATE" && log_message "checkfaves.sh: copied $FAVOURITE_FILE into $PREVIOUS_STATE"
            fi
        else
            touch $FAVOURITE_FILE && log_message "checkfaves.sh: created $FAVOURITE_FILE"
        fi 

        # avoid potential busy looping
        sleep 1
    done
}

monitor_favourite_file &