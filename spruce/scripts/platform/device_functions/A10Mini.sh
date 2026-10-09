#!/bin/sh
# A10 Mini device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/dArkMossCommon.sh"

# The rk817 codec switches to the jack itself (codec-hp-det in the dts), and
# there is no jack state for spruce to read, so the base's path is left alone.
apply_playback_path() {
    :
}

# idlemon's default node is event3, which is the volume keys here. The js node,
# because emulators write rumble to the event node.
set_event_arg_for_idlemon() {
    EVENT_ARG="-e $(readlink -f /dev/input/by-path/platform-odroidgo3-joypad-joystick)"
}

device_get_charging_status() {
    if grep -qs "^1$" /sys/class/power_supply/ac/online /sys/class/power_supply/usb/online; then
        if [ "$(cat "$BATTERY/capacity" 2>/dev/null)" = "100" ]; then
            echo "Full"
        else
            echo "Charging"
        fi
    else
        echo "Discharging"
    fi
}

# The common defaults with this pad's udev numbering: select 12, L3 14.
set_default_ra_hotkeys() {
    RA_FILE="/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"12\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"4\"" \
        "input_save_state_btn = \"5\"" \
        "input_menu_toggle = \"f1\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_toggle_fast_forward_btn = \"14\"" \
        "input_screenshot_btn = \"nul\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"nul\"" \
        "input_state_slot_increase_btn = \"nul\"" \
        "input_toggle_slowmotion_btn = \"nul\""
}

# No sticks: dArkMoss's joypad driver can report the d-pad as the left stick.
DPAD_ANALOG="/sys/devices/platform/odroidgo3-joypad/dpad_analog"
_a10_dpad_analog() {
    [ -w "$DPAD_ANALOG" ] || return 0
    printf '%s' "$1" > "$DPAD_ANALOG"
    log_message "A10 Mini d-pad as stick: $1"
}

# MENU+SELECT in game flips it, for games that only listen to the stick.
swap_dpad_analog_toggle() {
    flag_check "in_menu" && return 0
    case "$(cat "$DPAD_ANALOG" 2>/dev/null)" in
        1) _a10_dpad_analog 0 ;;
        *) _a10_dpad_analog 1 ;;
    esac
    vibrate &
}

treat_dpad_as_analog() {
    _a10_dpad_analog 1
}

treat_dpad_as_dpad() {
    _a10_dpad_analog 0
}
