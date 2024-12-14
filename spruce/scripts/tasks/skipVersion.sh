#!/bin/sh
if [ "$1" = "0" ]; then
    echo -n "Update downloader will skip version check after save and exit."
    return 0
fi

if [ "$1" = "1" ]; then
    echo -n "Only run this if needing to reinstall."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

UPDATER_FILE="/mnt/SDCARD/Updater/updater.sh"
OTA_FILE="/mnt/SDCARD/App/-OTA/downloader.sh"

# Update both files to set SKIP_VERSION_CHECK=true
sed -i 's/SKIP_VERSION_CHECK=false/SKIP_VERSION_CHECK=true/' "$UPDATER_FILE" "$OTA_FILE"

/mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh show /mnt/SDCARD/App/-OTA/config.json