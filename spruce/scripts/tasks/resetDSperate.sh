#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if rm -rf /mnt/SDCARD/Saves/dsperate; then
    log_message "dsperate configs have been reset."
else
    log_message "dsperate config nuke failed?"
fi
