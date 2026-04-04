#!/bin/sh

# Fix PPSSPP Pause hotkey in controls INI files
# - A30: old binding "Pause = 10-106" (wrong keycode) → "Pause = 10-196:10-191" (Select+Square)
# - Flip: old binding "Pause = 1-111,10-109,10-104" (keyboard/raw codes) → "Pause = 10-196:10-191"
# - Brick/SmartPro/SmartProS/AnbernicRGCubeXX: Pause line was missing entirely → add it
# All devices now use the same unified Select+Square combo for Pause.

TARGET_VERSION="4.1.2"

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"
if [ -f "$HELPER_FUNCTIONS" ]; then
    . "$HELPER_FUNCTIONS"
else
    echo "Error: helperFunctions.sh not found"
    exit 1
fi

log_message "Starting upgrade to version $TARGET_VERSION"

PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
NEW_PAUSE='Pause = 10-196:10-191'

patch_controls_file() {
    file="$1"
    [ -f "$file" ] || return 0

    if grep -q '^Pause = ' "$file"; then
        # Pause line exists — replace it if it doesn't already match
        current=$(grep '^Pause = ' "$file")
        if [ "$current" = "$NEW_PAUSE" ]; then
            log_message "$(basename "$file"): Pause already correct, skipping"
            return 0
        fi
        sed "s|^Pause = .*|$NEW_PAUSE|" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        log_message "$(basename "$file"): Updated Pause binding"
    else
        # Pause line missing — add it after Exit App (or at end of [ControlMapping] block)
        if grep -q '^Exit App = ' "$file"; then
            sed "/^Exit App = .*/a\\
$NEW_PAUSE" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            log_message "$(basename "$file"): Added Pause binding after Exit App"
        else
            echo "$NEW_PAUSE" >> "$file"
            log_message "$(basename "$file"): Appended Pause binding"
        fi
    fi
}

# Patch all per-platform controls files
for ini in "$PSP_DIR"/controls-*.ini; do
    patch_controls_file "$ini"
done

# Patch the active controls.ini (restored from backup, may be stale)
patch_controls_file "$PSP_DIR/controls.ini"

log_message "Upgrade to version $TARGET_VERSION completed successfully"
exit 0
