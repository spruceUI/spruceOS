#!/bin/sh

# Fix A30 RetroArch input mapping after restore
# - Set input_menu_toggle_btn to nul so the Guide button path works
#   (old value "9" broke standalone menu button toggle)
# - Add joypad _btn fallback values for hotkeys
#   (old configs only had keyboard bindings, no btn fallbacks)

TARGET_VERSION="4.1.1"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

RA_A30_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-A30.cfg"

if [ ! -f "$RA_A30_CFG" ]; then
    log_message "No retroarch-A30.cfg found, skipping A30 input fix"
    exit 0
fi

log_message "Starting upgrade to version $TARGET_VERSION"
log_message "Patching A30 RetroArch hotkey config"

# Fix menu toggle btn: must be nul for Guide button autoconfig path
sed 's|^input_menu_toggle_btn = .*|input_menu_toggle_btn = "nul"|' \
    "$RA_A30_CFG" > "$RA_A30_CFG.tmp" && mv "$RA_A30_CFG.tmp" "$RA_A30_CFG"

# Add joypad btn fallbacks for hotkeys (only replace nul values)
for pair in \
    "input_enable_hotkey_btn:6" \
    "input_exit_emulator_btn:0" \
    "input_fps_toggle_btn:2" \
    "input_load_state_btn:4" \
    "input_save_state_btn:5" \
    "input_screenshot_btn:1"
do
    key="${pair%%:*}"
    val="${pair##*:}"
    sed "s|^${key} = \"nul\"|${key} = \"${val}\"|" \
        "$RA_A30_CFG" > "$RA_A30_CFG.tmp" && mv "$RA_A30_CFG.tmp" "$RA_A30_CFG"
done

log_message "Upgrade to version $TARGET_VERSION completed successfully"
exit 0
