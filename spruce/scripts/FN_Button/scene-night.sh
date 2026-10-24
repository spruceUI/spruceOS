#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

DEVICE_CONFIG="$SYSTEM_JSON"
LOG_FILE=/tmp/scene-night.log
CONFIG_TMP="${DEVICE_CONFIG}.tmp.$$"

cleanup() {
    rm -f "$CONFIG_TMP"
}
trap cleanup EXIT

log_message "scene-night.sh: starting with arg '$1'"

fail() {
    log_message "scene-night.sh: $1"
    exit 1
}

if [ -z "$DEVICE_CONFIG" ] || [ ! -f "$DEVICE_CONFIG" ]; then
    fail "device config is unavailable: $DEVICE_CONFIG"
fi

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

apply_profile() {
    section="$1"

    backlight="$(jq -er --arg section "$section" '(.[$section].backlight // .backlight // 10) | tonumber | select(. >= 0 and . <= 20)' "$DEVICE_CONFIG" 2>> "$LOG_FILE")" ||
        fail "could not read a valid $section backlight from $DEVICE_CONFIG"
    brightness="$(jq -er --arg section "$section" '(.[$section].brightness // .brightness // 10) | tonumber | select(. >= 0 and . <= 20)' "$DEVICE_CONFIG" 2>> "$LOG_FILE")" ||
        fail "could not read a valid $section brightness from $DEVICE_CONFIG"
    contrast="$(jq -er --arg section "$section" '(.[$section].contrast // .contrast // 10) | tonumber | select(. >= 0 and . <= 20)' "$DEVICE_CONFIG" 2>> "$LOG_FILE")" ||
        fail "could not read a valid $section contrast from $DEVICE_CONFIG"
    hue="$(jq -er --arg section "$section" '(.[$section].hue // .hue // 10) | tonumber | select(. >= 0 and . <= 20)' "$DEVICE_CONFIG" 2>> "$LOG_FILE")" ||
        fail "could not read a valid $section hue from $DEVICE_CONFIG"
    saturation="$(jq -er --arg section "$section" '(.[$section].saturation // .saturation // 10) | tonumber | select(. >= 0 and . <= 20)' "$DEVICE_CONFIG" 2>> "$LOG_FILE")" ||
        fail "could not read a valid $section saturation from $DEVICE_CONFIG"

    apply_setting backlight set_backlight "$backlight"
    apply_setting brightness set_brightness "$brightness"
    apply_setting contrast set_contrast "$contrast"
    apply_setting hue set_hue "$hue"
    apply_setting saturation set_saturation "$saturation"
}

update_night_mode_state() {
    state="$1"

    jq --arg state "$state" '.nightMode = (if $state == "1" then 1 else 0 end)' "$DEVICE_CONFIG" > "$CONFIG_TMP" 2>> "$LOG_FILE" ||
        fail "could not update nightMode in $DEVICE_CONFIG"
    mv "$CONFIG_TMP" "$DEVICE_CONFIG" 2>> "$LOG_FILE" ||
        fail "could not save nightMode to $DEVICE_CONFIG"
}

case "$1" in
    1)
        apply_profile "nightModeSettings"
        update_night_mode_state "1"
        ;;
    0)
        apply_profile "defaultModeSettings"
        update_night_mode_state "0"
        ;;
esac