#!/bin/sh
# GKD Pixel 2 on dArkMoss: what is particular to this unit (the rest is in
# dArkMossCommon.sh). Pixel2.sh belongs to the Twig-Next base and is not used.

. "/mnt/SDCARD/spruce/scripts/platform/darkmoss/dArkMossCommon.sh"

# Playback path: dArkMossCommon's apply_playback_path, on the extcon jack state the cfg finds;
# the base's pixel2-jack.sh does the same on every plug event.

# The js node, as on the other dArkMoss units: emulators write rumble to the event node.
set_event_arg_for_idlemon() {
    EVENT_ARG="-e $(readlink -f /dev/input/by-path/platform-gamekiddy-joypad-joystick)"
}

# udev numbering in key-code order: select 8, L2 6, R2 7, the driver's phantom THUMBR 10,
# F1 15; fast forward on R2. Player 1 is bound in retroarch-Pixel2DarkMoss.cfg.
set_default_ra_hotkeys() {
    RA_FILE="$(platform_path "/mnt/SDCARD/Saves/ra-configs/retroarch-%s.cfg")"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"8\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"4\"" \
        "input_save_state_btn = \"5\"" \
        "input_menu_toggle = \"f1\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_toggle_fast_forward_btn = \"7\"" \
        "input_screenshot_btn = \"nul\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"nul\"" \
        "input_state_slot_increase_btn = \"nul\"" \
        "input_toggle_slowmotion_btn = \"nul\""
}
