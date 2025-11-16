#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

RA_FILE="/mnt/SDCARD/RetroArch/retroarch.cfg"

update_file() {
    file="$1"
    shift

    for setting in "$@"; do
        if grep -q "${setting%%=*}" "$file"; then
            sed -i "s|^${setting%%=*}.*|$setting|" "$file"
        else
            echo "$setting" >>"$file"
        fi
    done

    log_message "Updated $file"
}

log_message "Resetting RetroArch hotkeys to Spruce defaults."

# Update RetroArch config with default values
update_file "$RA_FILE" \
    "input_enable_hotkey = \"rctrl\"" \
    "input_exit_emulator = \"ctrl\"" \
    "input_fps_toggle = \"alt\"" \
    "input_joypad_driver = \"linuxraw\"" \
    "input_load_state = \"tab\"" \
    "input_menu_toggle = \"shift\"" \
    "input_menu_toggle_btn = \"9\"" \
    "input_player1_l_x_minus_axis = \"-0\"" \
    "input_player1_l_x_plus_axis = \"+0\"" \
    "input_player1_l_y_minus_axis = \"-1\"" \
    "input_player1_l_y_plus_axis = \"+1\"" \
    "input_quit_gamepad_combo = \"0\"" \
    "input_save_state = \"backspace\"" \
    "input_screenshot = \"space\"" \
    "input_shader_toggle = \"up\"" \
    "input_state_slot_decrease = \"left\"" \
    "input_state_slot_increase = \"right\"" \
    "input_toggle_slowmotion = \"e\"" \
    "input_toggle_fast_forward = \"t\""

log_message "RetroArch hotkeys have been reset to defaults."
