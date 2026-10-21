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

apply_setting() {
    setting="$1"
    setter="$2"
    value="$3"

    if ! command -v "$setter" >/dev/null 2>&1; then
        log_message "scene-night.sh: $setter is unavailable; skipping $setting"
        return 0
    fi

    "$setter" "$value" 2>> "$LOG_FILE" ||
        fail "$setter $value failed while applying $setting"
}

restore_setting() {
    setting="$1"
    setter="$2"

    if ! command -v "$setter" >/dev/null 2>&1; then
        log_message "scene-night.sh: $setter is unavailable; skipping restore of $setting"
        return 0
    fi

    value="$(jq -er --arg key "$setting" '.[$key] | numbers' "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE")" ||
        fail "could not read saved $setting from $SAVED_SETTINGS_FILE"
    "$setter" "$value" 2>> "$LOG_FILE" ||
        fail "$setter $value failed while restoring $setting"
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
        apply_setting backlight set_backlight "$backlight"
        apply_setting brightness set_brightness "$brightness"
        apply_setting contrast set_contrast "$contrast"
        apply_setting hue set_hue "$hue"
        apply_setting saturation set_saturation "$saturation"
        ;;
    0)
        # Restore the saved values when the switch returns to its normal state.
        if [ -f "$SAVED_SETTINGS_FILE" ]; then
            restore_setting backlight set_backlight
            restore_setting brightness set_brightness
            restore_setting contrast set_contrast
            restore_setting hue set_hue
            restore_setting saturation set_saturation
            rm -f "$SAVED_SETTINGS_FILE" 2>> "$LOG_FILE" || fail "could not remove $SAVED_SETTINGS_FILE"
        fi
        ;;
esac