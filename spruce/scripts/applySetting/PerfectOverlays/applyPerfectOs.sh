
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

# print minor info text with the value index zero (i.e. "on" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "0" ]; then
    echo -n "Provided by Mugwomp93 and 1PlayerInsertCoin"
    return 0
fi

# print minor info text with the value index one (i.e. "off" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "1" ]; then
    echo -n "Would apply to GB, GBC, and GBA consoles"
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$1" == "on" ]; then
    update_setting "perfect_overlays" "on"
    /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GB.sh apply
    /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBC.sh apply
    /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBA.sh apply
    log_message "Turning on Perfect Overlays"

elif [ "$1" == "off" ]; then
    update_setting "perfect_overlays" "off"
    /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GB.sh remove
    /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBC.sh remove
    /mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/GBA.sh remove
    log_message "Turning off Perfect Overlays"
fi
