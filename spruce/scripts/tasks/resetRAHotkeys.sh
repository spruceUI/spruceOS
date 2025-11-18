#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

RA_FILE="/mnt/SDCARD/spruce/settings/platform/retroarch-$PLATFORM.cfg"

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

if [ "$PLATFORM" = "A30" ]; then
    update_file "$RA_FILE" \
        "input_enable_hotkey = \"rctrl\"" \
        "input_exit_emulator = \"ctrl\"" \
        "input_fps_toggle = \"alt\"" \
        "input_load_state = \"tab\"" \
        "input_menu_toggle = \"shift\"" \
        "input_menu_toggle_btn = \"9\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_save_state = \"backspace\"" \
        "input_screenshot = \"space\"" \
        "input_shader_toggle = \"up\"" \
        "input_state_slot_decrease = \"left\"" \
        "input_state_slot_increase = \"right\"" \
        "input_toggle_slowmotion = \"e\"" \
        "input_toggle_fast_forward = \"t\""
else
    update_file "$RA_FILE" \
        "input_enable_hotkey_btn = \"4\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"9\"" \
        "input_menu_toggle = \"escape\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_save_state_btn = \"10\"" \
        "input_screenshot_btn = \"1\"" \
        "input_shader_toggle_btn = \"11\"" \
        "input_state_slot_decrease_btn = \"13\"" \
        "input_state_slot_increase_btn = \"14\"" \
        "input_toggle_slowmotion_axis = \"+4\"" \
        "input_toggle_fast_forward_axis = \"+5\""
fi

log_message "RetroArch hotkeys have been reset to defaults."
