#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Keep the active display values so switch-off can restore them.
SAVED_SETTINGS_FILE=/tmp/system/night_saved_display.json
SPRUCE_CONFIG=/mnt/SDCARD/Saves/spruce/spruce-config.json
LOG_FILE=/tmp/scene-night.log

log_message "scene-night.sh: starting with arg '$1'"

fail() {
    log_message "scene-night.sh: $1"
    exit 1
}

mkdir -p /tmp/system/ || fail "could not create /tmp/system"

case "$1" in
    1)
        # Read configured night values and validate them before changing the display.
        backlight="$(jq -er '.menuOptions["Night Mode Settings"].backlight.selected | tonumber | select(. >= 0 and . <= 20)' "$SPRUCE_CONFIG" 2>> "$LOG_FILE")" ||
            fail "could not read a valid night backlight from $SPRUCE_CONFIG"
        brightness="$(jq -er '.menuOptions["Night Mode Settings"].brightness.selected | tonumber | select(. >= 0 and . <= 20)' "$SPRUCE_CONFIG" 2>> "$LOG_FILE")" ||
            fail "could not read a valid night brightness from $SPRUCE_CONFIG"
        contrast="$(jq -er '.menuOptions["Night Mode Settings"].contrast.selected | tonumber | select(. >= 0 and . <= 20)' "$SPRUCE_CONFIG" 2>> "$LOG_FILE")" ||
            fail "could not read a valid night contrast from $SPRUCE_CONFIG"
        hue="$(jq -er '.menuOptions["Night Mode Settings"].hue.selected | tonumber | select(. >= 0 and . <= 20)' "$SPRUCE_CONFIG" 2>> "$LOG_FILE")" ||
            fail "could not read a valid night hue from $SPRUCE_CONFIG"
        saturation="$(jq -er '.menuOptions["Night Mode Settings"].saturation.selected | tonumber | select(. >= 0 and . <= 20)' "$SPRUCE_CONFIG" 2>> "$LOG_FILE")" ||
            fail "could not read a valid night saturation from $SPRUCE_CONFIG"

        # Save the active display values before applying the configured night values.
        jq '{backlight, brightness, contrast, hue, saturation}' "$SYSTEM_JSON" > "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE" ||
            fail "could not save current display values from $SYSTEM_JSON"
        set_backlight "$backlight" 2>> "$LOG_FILE" || fail "set_backlight $backlight failed"
        set_brightness "$brightness" 2>> "$LOG_FILE" || fail "set_brightness $brightness failed"
        set_contrast "$contrast" 2>> "$LOG_FILE" || fail "set_contrast $contrast failed"
        set_hue "$hue" 2>> "$LOG_FILE" || fail "set_hue $hue failed"
        set_saturation "$saturation" 2>> "$LOG_FILE" || fail "set_saturation $saturation failed"
        ;;
    0)
        # Restore the saved values when the switch returns to its normal state.
        if [ -f "$SAVED_SETTINGS_FILE" ]; then
            backlight="$(jq -er '.backlight | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
                fail "could not read saved backlight from $SAVED_SETTINGS_FILE"
            brightness="$(jq -er '.brightness | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
                fail "could not read saved brightness from $SAVED_SETTINGS_FILE"
            contrast="$(jq -er '.contrast | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
                fail "could not read saved contrast from $SAVED_SETTINGS_FILE"
            hue="$(jq -er '.hue | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
                fail "could not read saved hue from $SAVED_SETTINGS_FILE"
            saturation="$(jq -er '.saturation | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
                fail "could not read saved saturation from $SAVED_SETTINGS_FILE"
            set_backlight "$backlight" 2>> "$LOG_FILE" || fail "restoring backlight to $backlight failed"
            set_brightness "$brightness" 2>> "$LOG_FILE" || fail "restoring brightness to $brightness failed"
            set_contrast "$contrast" 2>> "$LOG_FILE" || fail "restoring contrast to $contrast failed"
            set_hue "$hue" 2>> "$LOG_FILE" || fail "restoring hue to $hue failed"
            set_saturation "$saturation" 2>> "$LOG_FILE" || fail "restoring saturation to $saturation failed"
            rm -f "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE" || fail "could not remove $SAVED_SETTINGS_FILE"
        fi
        ;;
esac