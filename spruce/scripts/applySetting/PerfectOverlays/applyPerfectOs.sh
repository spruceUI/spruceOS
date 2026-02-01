#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$1" == "True" ]; then
    if ! flag_check "perfectOverlays"; then
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GB.sh apply
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBC.sh apply
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBA.sh apply
        log_message "Turning on Perfect Overlays"
        flag_add "perfectOverlays"
    fi
elif [ "$1" == "False" ]; then
    if flag_check "perfectOverlays"; then
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GB.sh remove
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBC.sh remove
        /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBA.sh remove
        log_message "Turning off Perfect Overlays"
        flag_remove "perfectOverlays"
    fi
fi
