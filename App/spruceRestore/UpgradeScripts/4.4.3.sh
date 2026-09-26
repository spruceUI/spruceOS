#!/bin/sh

TARGET_VERSION="4.4.3"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# RetroAchievements renamed Softcore to Casual and so did the mode toggle.
# Rename a saved Softcore selection so merge_configs.py keeps it instead of
# dropping it back to the shipped default.
for _cfg in /mnt/SDCARD/Saves/spruce/spruce-config.json /mnt/SDCARD/Saves/spruce/backups/spruce-config.json; do
    [ -f "$_cfg" ] || continue
    if [ "$(jq -r '.menuOptions."RetroAchievements Settings".modeToggle.selected // ""' "$_cfg")" = "Softcore" ]; then
        jq '.menuOptions["RetroAchievements Settings"].modeToggle.selected = "Casual"' "$_cfg" > "$_cfg.tmp" && mv "$_cfg.tmp" "$_cfg"
        log_message "Renamed RetroAchievements mode Softcore to Casual in $_cfg"
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
