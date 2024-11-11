#!/bin/sh
if [ "$1" == "0" ]; then
    echo -n "Emufresh will be reset on save and exit."
    return 0
fi

if [ "$1" == "1" ]; then
    echo -n "Use this to trigger a full reset of Emufresh. Helpful if your displayed roms or consoles are incorrect."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

MD5_PATH="/mnt/SDCARD/Emu/.emu_setup/md5"

rm -r "$MD5_PATH" 
log_message "emufresh: removed $MD5_PATH and its contents"
