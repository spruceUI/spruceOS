#!/bin/sh

TARGET_VERSION="4.4.2"

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

# RetroArch rewrites its config on exit, so an RGB30 config nobody edited was
# kept above and would miss the 4.4.2 hotkey defaults. Move each hotkey that is
# still at its 4.4.1 default; anything the user changed stays as it is.
RGB30_CFG="$NEW_CFG_DIR/retroarch-RGB30.cfg"
if [ -f "$RGB30_CFG" ]; then
    for _hotkey in \
        "input_fps_toggle_btn 2 3" \
        "input_menu_toggle_btn 3 2" \
        "input_screenshot_btn nul 1" \
        "input_shader_toggle_btn nul 13" \
        "input_state_slot_decrease_btn nul 15" \
        "input_state_slot_increase_btn nul 16" \
        "input_toggle_fast_forward_btn 10 7" \
        "input_toggle_slowmotion_btn nul 6"
    do
        set -- $_hotkey
        sed "s|^$1 = \"$2\"\$|$1 = \"$3\"|" "$RGB30_CFG" > "$RGB30_CFG.tmp" && mv "$RGB30_CFG.tmp" "$RGB30_CFG"
    done
    log_message "Moved RGB30 RetroArch hotkeys still at their 4.4.1 defaults to the 4.4.2 ones."
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
