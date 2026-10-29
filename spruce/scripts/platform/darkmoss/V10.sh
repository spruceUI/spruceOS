#!/bin/sh
# Powkiddy V10 device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/darkmoss/dArkMossCommon.sh"

# The rk817 codec switches to the jack itself on the OGA 1.1 kernel, and there
# is no jack state file for spruce to read, so the base's path is left alone.
# UNVERIFIED: on this V10 the jack switch reads inverted (seen under the
# NextUI port, which had to flip it). If headphones stay silent, this is where
# a watcher on the rk817 jack input goes.
apply_playback_path() {
    :
}

# idlemon's default node is the power key here. The js node, because
# emulators write rumble to the event node.
set_event_arg_for_idlemon() {
    EVENT_ARG="-e $(readlink -f /dev/input/by-path/platform-odroidgo2-joypad-joystick)"
}

# No sticks: dArkMoss's joypad driver can report the d-pad as the left stick.
DPAD_ANALOG="/sys/devices/platform/odroidgo2-joypad/dpad_analog"
_v10_dpad_analog() {
    [ -w "$DPAD_ANALOG" ] || return 0
    printf '%s' "$1" > "$DPAD_ANALOG"
    log_message "V10 d-pad as stick: $1"
}

# MENU+SELECT in game flips it, for games that only listen to the stick.
swap_dpad_analog_toggle() {
    flag_check "in_menu" && return 0
    case "$(cat "$DPAD_ANALOG" 2>/dev/null)" in
        1) _v10_dpad_analog 0 ;;
        *) _v10_dpad_analog 1 ;;
    esac
    vibrate &
}

treat_dpad_as_analog() {
    _v10_dpad_analog 1
}

treat_dpad_as_dpad() {
    _v10_dpad_analog 0
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

# The memory clock must not move: every change stalls the bus and the sound
# crackles (measured on a V10). The 4.4 kernel's dmc offers no "performance"
# governor, so every CPU mode pins it with "userspace" at its top frequency.
set_dram_governor() {
    [ -n "$DRAM_DEVFREQ_DIR" ] && [ -d "$DRAM_DEVFREQ_DIR" ] || return 0
    _top=$(tr ' ' '\n' < "$DRAM_DEVFREQ_DIR/available_frequencies" 2>/dev/null | grep -v '^$' | sort -n | tail -1)
    [ -n "$_top" ] || return 0
    echo userspace > "$DRAM_DEVFREQ_DIR/governor" 2>/dev/null
    echo "$_top" > "$DRAM_DEVFREQ_DIR/userspace/set_freq" 2>/dev/null
    echo "$_top" > "$DRAM_DEVFREQ_DIR/min_freq" 2>/dev/null
}

# This pad's udev numbering (RetroArch autoconfig "GO-Advance Gamepad (rev 1.1)"):
# select 12, R2 15. No stick clicks, so fast forward goes on R2.
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
        "input_toggle_fast_forward_btn = \"15\"" \
        "input_screenshot_btn = \"nul\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"nul\"" \
        "input_state_slot_increase_btn = \"nul\"" \
        "input_toggle_slowmotion_btn = \"nul\""
}
