#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/trimui_a133p.sh"

export_ld_library_path() {
    export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib"
}

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/smartpro-system.json"
}

init_gpio_a133p() {
    #PD11 pull high for VCC-5v
    echo 107 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio107/direction
    echo -n 1 > /sys/class/gpio/gpio107/value

    #rumble motor PH3
    echo 227 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio227/direction
    echo -n 0 > /sys/class/gpio/gpio227/value

    #Left/Right Pad PD14/PD18
    echo 110 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio110/direction
    echo -n 1 > /sys/class/gpio/gpio110/value

    echo 114 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio114/direction
    echo -n 1 > /sys/class/gpio/gpio114/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    echo -n in > /sys/class/gpio/gpio243/direction
}

runtime_mounts_a133p() {
    # Mask Roms/PORTS with non-A30 version
    mkdir -p "/mnt/SDCARD/Roms/PORTS64"
    mount --bind "/mnt/SDCARD/Roms/PORTS64" "/mnt/SDCARD/Roms/PORTS" &    
    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    /mnt/SDCARD/spruce/brick/sdl2/bind.sh &
    wait
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/flip/bin/MainUI
}

update_ra_config_file_with_new_setting() {
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


set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    # Update RetroArch config with default values

    if [ "$PLATFORM" = "A30" ]; then
        update_ra_config_file_with_new_setting "$RA_FILE" \
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
        update_ra_config_file_with_new_setting "$RA_FILE" \
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

}