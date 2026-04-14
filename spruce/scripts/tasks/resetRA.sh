#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh



log_message "Resetting RetroArch config to default."
case "$PLATFORM" in
    "Anbernic"*)
        ORIGINAL_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG_XX-universal.cfg"
        BACKUP_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG_XX-universal.cfg.bak"
        ;;
    *)
        ORIGINAL_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
        BACKUP_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg.bak"
        ;;
esac
cp -f $BACKUP_RA_FILE $ORIGINAL_RA_FILE