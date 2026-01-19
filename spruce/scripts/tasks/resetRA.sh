#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ORIGINAL_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
BACKUP_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg.bak"

log_message "Resetting RetroArch config to default."
cp -f $BACKUP_RA_FILE $ORIGINAL_RA_FILE