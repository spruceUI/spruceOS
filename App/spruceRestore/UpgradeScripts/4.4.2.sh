#!/bin/sh

# -------------------- UPGRADE SCRIPT TEMPLATE --------------------
# Instructions:
# 1. Set the TARGET_VERSION to the version you're upgrading to.
# 2. Add your file updates in the designated section using the update_file function.
# 3. Ensure all paths are correct for your specific upgrade scenario.
# 4. Add any additional upgrade steps as needed.

# Define the target version for this upgrade script
TARGET_VERSION="X.Y.Z"  # Replace X.Y.Z with your target version number

/mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Source the helper functions
HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# NEW LIVE RA CONFIG LOCATION
# Per-platform RA configs are being moved from the RetroArch/platform/ folder into
# Saves/ra-configs/ -- this allows us to no longer concern ourselves with including
# them in the spruceBackup flow, which reduces the chance of backup/restore bugs
# when onboarding new devices. This update script is intended to handle the transition
# between these locations for existing spruce users.

OLD_CFG_DIR=/mnt/SDCARD/RetroArch/platform
NEW_CFG_DIR=/mnt/SDCARD/Saves/ra-configs

mkdir -p "$NEW_CFG_DIR"

# Don't move the old config if it's the same as the .bak; the user never touched this file,
# so there's no need to keep it. Otherwise, move it into the new location. We use mv -f
# because we want the restore to always work even if there's already a file at its destination.
# Skip over the non-base configs, for which we do not ship a .bak file.
for _cfg in "$OLD_CFG_DIR"/*.cfg ; do

    if [ -f "$_cfg.bak" ]; then

        if [ "$(cat "$_cfg")" = "$(cat "$_cfg.bak")" ]; then
            rm "$_cfg"
            log_message "Deleted stale $_cfg with no differences from its .bak ."

        else
            mv -f "$_cfg" "$NEW_CFG_DIR"/"$(basename "$_cfg")"
            log_message "Moved $_cfg into $NEW_CFG_DIR ."
        fi
    fi

done



# -------------------- UPGRADE COMPLETION --------------------
# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi
