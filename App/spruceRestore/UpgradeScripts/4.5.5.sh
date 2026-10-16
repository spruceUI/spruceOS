#!/bin/sh

TARGET_VERSION="4.5.5"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# dArkMoss system jsons moved from App/PyUI/config to Saves. Overwrite: boot may
# already have seeded a default there.
OLD_CONFIG_DIR=/mnt/SDCARD/App/PyUI/config
for _name in rgb30 rgb20sx miniloong a10mini g350 xumini; do
    _old="$OLD_CONFIG_DIR/$_name-system.json"
    [ -f "$_old" ] || continue
    mv -f "$_old" "/mnt/SDCARD/Saves/$_name-system.json" && log_message "Moved $_old to Saves"
done
rmdir "$OLD_CONFIG_DIR" 2>/dev/null


# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
