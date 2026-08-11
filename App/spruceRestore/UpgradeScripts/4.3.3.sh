#!/bin/sh

# Clear the rom list cache written by 4.3.0 - 4.3.2
#
# Those versions decided whether a cached rom listing was still good by checking
# the folder's modification date. That date is not trustworthy: archive tools
# (7-Zip, WinRAR, Windows' built in extract) write the date stored inside the
# archive back onto the folder after extracting into it, so a folder can gain
# games while its date stays put or moves backwards. When that happened the
# cached listing was kept and the new games never appeared, permanently.
#
# 4.3.3 confirms cached listings in the background and corrects them, so a stale
# cache now repairs itself. Clearing it here just means affected users get the
# right list the first time they open a system instead of seeing the old one
# flash up once beforehand.

TARGET_VERSION="4.3.3"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

log_message "Starting upgrade to version $TARGET_VERSION"

ROM_LIST_CACHE="/mnt/SDCARD/Saves/cache"

if [ -d "$ROM_LIST_CACHE" ]; then
    cached_count=$(find "$ROM_LIST_CACHE" -maxdepth 1 -name '*.json' | wc -l)
    rm -rf "$ROM_LIST_CACHE"
    log_message "Removed rom list cache ($cached_count cached folder listings)"
else
    log_message "No rom list cache present, nothing to clear"
fi

log_message "Upgrade to version $TARGET_VERSION completed successfully"
exit 0
