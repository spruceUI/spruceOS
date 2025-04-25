#!/bin/sh

# Favorites do not show up in MainUI on the Flip unless they use the /media/sdcard0 path, even though
# /mnt/SDCARD and /media/sdcard0 are symlinks to the same path. The problem is that the oppopsite is
# true of the other spruce devices. This script is used to translate the rom paths in favourite.json 
# to and from those two SD card paths, depending on the device that spruce is booting on at the time.
# This needs to happen BEFORE MainUI loads.

# This script also handles hiding and showing ROMs on the favorites and recents lists that live on
# the second (non-spruce system) SD card, depending on whether it is inserted or not. It does this
# by changing the "type" field for that ROM's entry in the json from 5 (for game) to null (for...
# nothing) and back, as appropriate.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

MNT_PATH=/mnt/SDCARD
MEDIA_PATH=/media/sdcard0
TF2_PATH=/media/sdcard1
FAVE_JSON_PATH=/mnt/SDCARD/Roms/favourite.json
RECENT_JSON_PATH=/mnt/SDCARD/Roms/recentlist.json

if [ "$PLATFORM" = "Flip" ]; then
    log_message "Flip detected - translating Favorites and Recents paths from /mnt/SDCARD to /media/sdcard0"
    sed -i "s|$MNT_PATH|$MEDIA_PATH|g" "$FAVE_JSON_PATH"
    sed -i "s|$MNT_PATH|$MEDIA_PATH|g" "$RECENT_JSON_PATH"

    if [ -d "$TF2_PATH/Roms" ]; then
        log_message "Second Roms card detected - revealing any favorites and recents on this card"
        sed -i "\|$TF2_PATH| s|\"type\"[ ]*:[ ]*null|\"type\": 5|" "$FAVE_JSON_PATH"
        sed -i "\|$TF2_PATH| s|\"type\"[ ]*:[ ]*null|\"type\": 5|" "$RECENT_JSON_PATH"
    else
        log_message "Second Roms card absent - hiding any favorites and recents from this card"
        sed -i "\|$TF2_PATH| s|\"type\":[ ]*[0-9]\+|\"type\": null|" "$FAVE_JSON_PATH"
        sed -i "\|$TF2_PATH| s|\"type\":[ ]*[0-9]\+|\"type\": null|" "$RECENT_JSON_PATH"
    fi
else
    log_message "Non-Flip detected - translating Favorites and Recents paths from /media/sdcard0 to /mnt/SDCARD"
    sed -i "s|$MEDIA_PATH|$MNT_PATH|g" "$FAVE_JSON_PATH"
    sed -i "s|$MEDIA_PATH|$MNT_PATH|g" "$RECENT_JSON_PATH"
fi
