#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
TEMP_FILE="/tmp/favourite.tmp"
TEMP_FILE2="/tmp/favourite.tmp2"

fix_fav_file() {
    # extract fields in fixed order
    jq -r -c '. | {label, system:(.launch | split("/") | .[4]), launch, rompath, type}' "$FAVOURITE_FILE" > $TEMP_FILE

    # add system postfix
    jq -r -c '. | .system as $SYS | if .label | endswith( " (" + $SYS + ")" ) then {label, launch, rompath, type} else {label:(.label+" ("+$SYS+")"), launch, rompath, type} end' "$TEMP_FILE" > $TEMP_FILE2

    # sort file
    sort $TEMP_FILE2 > $TEMP_FILE

    # remove duplicated lines 
    awk '!seen[$0]++' $TEMP_FILE > $FAVOURITE_FILE

    rm $TEMP_FILE
    rm $TEMP_FILE2
    
    #cat $FAVOURITE_FILE
}

monitor_favourite_file() {
    log_message "checkfaves.sh: begin monitoring favourites file"
    while true; do
        if [ -f "$FAVOURITE_FILE" ]; then
            log_message "checkfaves.sh: $FAVOURITE_FILE exists"
            inotifywait -e modify $FAVOURITE_FILE

            log_message "checkfaves.sh: fix $FAVOURITE_FILE"
            fix_fav_file
        else
            touch $FAVOURITE_FILE && log_message "checkfaves.sh: created $FAVOURITE_FILE"
        fi 

        # avoid potential busy looping
        sleep 1
    done
}

monitor_favourite_file &