#!/bin/sh

TARGET_VERSION="4.5.3"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# The old BaseOS shim execs .tmp_update/anbernic.sh, which 4.5.2 removed. BaseOS
# 1.3.0 prefers this path over spruce's runtime.sh, so a card that kept the shim
# loops at boot. Remove it only if it is ours, not a NextUI install's.
SHIM_DIR=/mnt/SDCARD/.system/h700/paks/MinUI.pak
if grep -q "anbernic.sh" "$SHIM_DIR/launch.sh" 2>/dev/null; then
    rm -f "$SHIM_DIR/launch.sh"
    rmdir "$SHIM_DIR" /mnt/SDCARD/.system/h700/paks /mnt/SDCARD/.system/h700 /mnt/SDCARD/.system 2>/dev/null
    log_message "Removed the old BaseOS shim $SHIM_DIR/launch.sh"
fi


# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
