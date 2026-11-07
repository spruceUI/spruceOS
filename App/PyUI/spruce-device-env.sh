#!/bin/sh
# The spruce side of PyUI's env-driven SPRUCE device (main-ui/devices/env/env_var_device.py).
# launch.sh sources this when the platform cfg sets PYUI_ENV_DEVICE=true. Every variable
# EnvVarDevice reads that the cfg has not set itself is filled in from spruce's own exports:
#   SCREEN_WIDTH/HEIGHT/ROTATION      DISPLAY_WIDTH/HEIGHT/ROTATION
#   SYSTEM_CFG_PATH                   SYSTEM_JSON (DEFAULT_CFG_PATH, the seed, is the cfg's)
#   PYUI_DEVICE_NAMES                 device_names, all lines
#   CONTROLLER_EVENT_PATH             EVENT_PATH_READ_INPUTS_SPRUCE
#   CONTROLLER_KEY_MAPPINGS           the B_* button codes
#   LEFT/RIGHT_STICK_X/Y_AXIS         STICK_LEFT/UP and STICK_LEFT_2/UP_2, per DEVICE_NUM_ANALOG_STICKS
#   STICK_INVERT_X/Y                  true when STICK_LEFT/UP's value is positive
#   TOUCH_EVENT_PATH                  EVENT_PATH_TOUCH
#   POWER_KEY_WATCHER_PATH            EVENT_PATH_POWER
#   VOL_KEY_WATCHER_PATH              EVENT_PATH_VOLUME, else the pad
#   POWER_BUTTON/VOLUME_UP/DOWN_KEYCODE  B_POWER, B_VOLUP, B_VOLDOWN
#   BATTERY_PERCENT_PATH              $BATTERY/capacity, unless the cfg sets BATTERY_PERCENT_CMD
#   CHARGE_STATUS_PATH                $BATTERY/status, unless the cfg sets CHARGE_STATUS_CMD
#   SUPPORTS_WIFI                     wifi_available_on_device, unless the cfg sets CHECK_WIFI_SUPPORT_CMD
#   BACKLIGHT_CMD                     set-backlight.sh, if the device defines apply_backlight
#   CONTRAST/SATURATION/BRIGHTNESS/HUE_CMD  set-display.sh, if it defines apply_display_<setting>
#   FW_VERSION                        device_get_fw_version, if defined
#   HAS_FFMPEG                        ffmpeg on PATH, which PyUI's image resizing runs
#   ROMS/FAVORITES/RECENTS/APPS_CONFIG/COLLECTIONS/STATE_PATH  spruce's fixed paths
# PyUI has no default for these, so the cfg sets them: POWER_OFF_CMD, REBOOT_CMD (unset: no
# reboot), CONTROLLER_EVENT_FORMAT, and STICK_DEADZONE when it has sticks (else PyUI ignores them).

# Exports $1 with the value $2 unless the cfg already set it; an empty value stays unset.
spruce_env_default() {
    if eval "[ -n \"\${$1}\" ]"; then
        # shellcheck disable=SC2163 # exports the variable named in $1
        export "$1"
    elif [ -n "$2" ]; then
        export "$1=$2"
    fi
}

# The code in a "type code [value]" definition, when it is of type $1.
spruce_env_code() {
    case "$2" in
        "$1 "*) _rest="${2#"$1 "}"; echo "${_rest%% *}" ;;
    esac
}

# "true" when a stick definition's value is positive: its left (or up) is the positive end.
spruce_env_inverted() {
    case "$1" in
        "3 "*" "[0-9]*) echo true ;;
        "3 "*) echo false ;;
    esac
}

# The B_* codes as CONTROLLER_KEY_MAPPINGS JSON. L3 and R3 are stick clicks, so a device
# without sticks maps neither: the Brick's two codes are its Fn keys.
spruce_env_key_mappings() {
    _buttons="A:A B:B X:X Y:Y L1:L1 L2:L2 R1:R1 R2:R2 START:START SELECT:SELECT MENU:MENU HOME:HOME"
    _buttons="$_buttons UP:DPAD_UP DOWN:DPAD_DOWN LEFT:DPAD_LEFT RIGHT:DPAD_RIGHT"
    [ "${DEVICE_NUM_ANALOG_STICKS:-0}" -gt 0 ] && _buttons="$_buttons L3:L3 R3:R3"
    for _button in $_buttons; do
        eval "echo \"${_button#*:} \$B_${_button%%:*}\""
    done | awk '
        function add(type, code, value, results) {
            json = json sep "{\"type\":" type ",\"code\":" code ",\"value\":" value ",\"results\":[" results "]}"
            sep = ","
        }
        function result(input, state) { return "{\"input\":\"" input "\",\"state\":\"" state "\"}" }
        # A key presses at 1 and releases at 0.
        $2 == 1 && $3 ~ /^[0-9]+$/ { add(1, $3, 1, result($1, "PRESS")); add(1, $3, 0, result($1, "RELEASE")) }
        # An axis button presses at its value; 0 releases every button on that axis.
        $2 == 3 && $3 ~ /^[0-9]+$/ && $4 ~ /^-?[0-9]+$/ && $4 != 0 {
            add(3, $3, $4, result($1, "PRESS"))
            prefix = ($3 in released) ? released[$3] "," : ""
            released[$3] = prefix result($1, "RELEASE")
        }
        END { for (code in released) add(3, code, 0, released[code]); print "[" json "]" }'
}

spruce_env_default SCREEN_WIDTH "$DISPLAY_WIDTH"
spruce_env_default SCREEN_HEIGHT "$DISPLAY_HEIGHT"
spruce_env_default SCREEN_ROTATION "$DISPLAY_ROTATION"
spruce_env_default SYSTEM_CFG_PATH "$SYSTEM_JSON"
spruce_env_default AUDIO_PLAYER "SDL2"
spruce_env_default PYUI_DEVICE_NAMES "$(device_names | tr '\n' ',' | sed 's/,$//')"

spruce_env_default CONTROLLER_EVENT_PATH "$EVENT_PATH_READ_INPUTS_SPRUCE"
spruce_env_default CONTROLLER_KEY_MAPPINGS "$(spruce_env_key_mappings)"
if [ "${DEVICE_NUM_ANALOG_STICKS:-0}" -ge 1 ]; then
    spruce_env_default LEFT_STICK_X_AXIS "$(spruce_env_code 3 "$STICK_LEFT")"
    spruce_env_default LEFT_STICK_Y_AXIS "$(spruce_env_code 3 "$STICK_UP")"
    spruce_env_default STICK_INVERT_X "$(spruce_env_inverted "$STICK_LEFT")"
    spruce_env_default STICK_INVERT_Y "$(spruce_env_inverted "$STICK_UP")"
fi
if [ "${DEVICE_NUM_ANALOG_STICKS:-0}" -ge 2 ]; then
    spruce_env_default RIGHT_STICK_X_AXIS "$(spruce_env_code 3 "$STICK_LEFT_2")"
    spruce_env_default RIGHT_STICK_Y_AXIS "$(spruce_env_code 3 "$STICK_UP_2")"
fi
spruce_env_default POWER_KEY_WATCHER_PATH "$EVENT_PATH_POWER"
spruce_env_default TOUCH_EVENT_PATH "$EVENT_PATH_TOUCH"
spruce_env_default VOL_KEY_WATCHER_PATH "${EVENT_PATH_VOLUME:-$EVENT_PATH_READ_INPUTS_SPRUCE}"
spruce_env_default POWER_BUTTON_KEYCODE "$(spruce_env_code 1 "$B_POWER")"
spruce_env_default VOLUME_UP_KEYCODE "$(spruce_env_code 1 "$B_VOLUP")"
spruce_env_default VOLUME_DOWN_KEYCODE "$(spruce_env_code 1 "$B_VOLDOWN")"

# A cfg command (get-device-status.sh) replaces the file read or the answer fixed at launch.
if [ -n "$BATTERY" ]; then
    [ -n "$BATTERY_PERCENT_CMD" ] || spruce_env_default BATTERY_PERCENT_PATH "$BATTERY/capacity"
    [ -n "$CHARGE_STATUS_CMD" ] || spruce_env_default CHARGE_STATUS_PATH "$BATTERY/status"
fi
if [ -n "$CHECK_WIFI_SUPPORT_CMD" ]; then
    :
elif wifi_available_on_device; then
    spruce_env_default SUPPORTS_WIFI "true"
else
    spruce_env_default SUPPORTS_WIFI "false"
fi

# Hardware goes through PyUI's action scripts, for the hooks this device's functions define.
command -v apply_backlight >/dev/null 2>&1 &&
    spruce_env_default BACKLIGHT_CMD "/mnt/SDCARD/App/PyUI/set-backlight.sh"
for _setting in contrast saturation brightness hue; do
    command -v "apply_display_$_setting" >/dev/null 2>&1 &&
        spruce_env_default "$(echo "$_setting" | tr a-z A-Z)_CMD" "/mnt/SDCARD/App/PyUI/set-display.sh $_setting"
done
command -v device_get_fw_version >/dev/null 2>&1 &&
    spruce_env_default FW_VERSION "$(device_get_fw_version)"

command -v ffmpeg >/dev/null 2>&1 && spruce_env_default HAS_FFMPEG "true"
spruce_env_default CLEAR_DISPLAY_CACHE_BELOW_MB "100"
spruce_env_default ROMS_PATH "/mnt/SDCARD/Roms/"
spruce_env_default FAVORITES_PATH "/mnt/SDCARD/Saves/pyui-favorites.json"
spruce_env_default RECENTS_PATH "/mnt/SDCARD/Saves/pyui-recents.json"
spruce_env_default APPS_CONFIG_PATH "/mnt/SDCARD/Saves/pyui-apps.json"
spruce_env_default COLLECTIONS_PATH "/mnt/SDCARD/Collections/"
spruce_env_default STATE_PATH "/mnt/SDCARD/Saves/pyui-state.json"

unset _button _buttons _rest _setting
