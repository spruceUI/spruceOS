#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


log_message "Resetting RetroArch config for $PLATFORM to default."

LIVE_RA_CFG="/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg"
BAK_RA_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg.bak"

if [ -f "$LIVE_RA_CFG" ]; then
    if rm "$LIVE_RA_CFG" ; then
        log_message "Deleted $LIVE_RA_CFG. New copy will be restored from $BAK_RA_CFG on next run of RA."
        return 0
    else
        log_message "ERROR: Failed to delete $LIVE_RA_CFG."
        return 1
    fi
else
    log_message "No $LIVE_RA_CFG to delete. Exiting."
    return 1
fi
