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

# "Disable RGB LEDs" True/False became "RGB LEDs" On/Off: rename the key and
# map the saved choice so merge_configs.py carries it over.
_leds='.menuOptions."RGB LED Settings"'
for _cfg in /mnt/SDCARD/Saves/spruce/spruce-config.json /mnt/SDCARD/Saves/spruce/backups/spruce-config.json; do
    [ -f "$_cfg" ] || continue
    _old="$(jq -r "$_leds.disableLEDs.selected // \"\"" "$_cfg")"
    [ -n "$_old" ] || continue
    if [ "$_old" = "True" ]; then _new="Off"; else _new="On"; fi
    jq "$_leds.enableLEDs = ($_leds.disableLEDs | .selected = \"$_new\") | del($_leds.disableLEDs)" "$_cfg" > "$_cfg.tmp" && mv "$_cfg.tmp" "$_cfg"
    log_message "Renamed disableLEDs=$_old to enableLEDs=$_new in $_cfg"
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
