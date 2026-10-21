#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Keep the pre-night backlight and contrast so switch-off can restore them.
SAVED_SETTINGS_FILE=/tmp/system/night_saved_display.json
LOG_FILE=/tmp/scene-night.log

log_message "scene-night.sh: starting with arg '$1'"

fail() {
    log_message "scene-night.sh: $1"
    exit 1
}

mkdir -p /tmp/system/ || fail "could not create /tmp/system"

case "$1" in
    1)
        # Save the current backlight and contrast, then set both to their night levels.
        jq '{backlight, contrast}' "$SYSTEM_JSON" > "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE" ||
            fail "could not save current backlight and contrast from $SYSTEM_JSON"
        # Use the same set_backlight helper as fn-brightness.sh, but set an exact level.
        set_backlight 1 2>> "$LOG_FILE" || fail "set_backlight 1 failed"
        set_contrast 1 2>> "$LOG_FILE" || fail "set_contrast 1 failed"
        ;;
    0)
        # Restore the saved values when the switch returns to its normal state.
        if [ -f "$SAVED_SETTINGS_FILE" ]; then
            backlight="$(jq -er '.backlight | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
                fail "could not read saved backlight from $SAVED_SETTINGS_FILE"
            contrast="$(jq -er '.contrast | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
                fail "could not read saved contrast from $SAVED_SETTINGS_FILE"
            set_backlight "$backlight" 2>> "$LOG_FILE" || fail "restoring backlight to $backlight failed"
            set_contrast "$contrast" 2>> "$LOG_FILE" || fail "restoring contrast to $contrast failed"
            rm -f "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE" || fail "could not remove $SAVED_SETTINGS_FILE"
        fi
        ;;
esac