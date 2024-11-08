#!/bin/sh

# Define the target version for this upgrade script
TARGET_VERSION="3.0.0"

# Source the global functions
if [ -f /mnt/SDCARD/spruce/scripts/helperFunctions.sh ]; then
    . /mnt/SDCARD/spruce/scripts/helperFunctions.sh
else
    echo "Error: helperFunctions.sh not found, cannot proceed with the upgrade"
    exit 1
fi

# Update specific settings in a file
# Usage: update_file "file_path" "setting1=value1" "setting2=value2" ...
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

# Main execution
log_message "Starting upgrade to version $TARGET_VERSION"

# ----------------File Updates Here----------------
# Update specific files
update_file "/mnt/SDCARD/RetroArch/retroarch.cfg" \
    "content_show_add = \"false\"" \
    "content_show_explore = \"false\"" \
    "content_show_favorites = \"false\"" \
    "content_show_playlists = \"false\"" \
    "core_info_savestate_bypass = \"true\"" \
    "core_updater_buildbot_assets_url = \"http://buildbot.libretro.com/assets/\"" \
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
    "menu_show_core_updater = \"false\"" \
    "menu_unified_controls = \"true\"" \
    "notification_show_autoconfig = \"false\"" \
    "notification_show_save_state = \"true\"" \
    "quick_menu_show_add_to_favorites = \"false\"" \
    "quick_menu_show_core_options_flush = \"true\"" \
    "quick_menu_show_download_thumbnails = \"false\"" \
    "quick_menu_show_reset_core_association = \"false\"" \
    "quick_menu_show_savestate_submenu = \"false\"" \
    "quick_menu_show_set_core_association = \"false\"" \
    "quick_menu_show_start_recording = \"false\"" \
    "quick_menu_show_start_streaming = \"false\"" \
    "remap_save_on_exit = \"true\"" \
    "settings_show_accessibility = \"false\"" \
    "settings_show_playlists = \"false\"" \
    "settings_show_power_management = \"false\"" \
    "settings_show_recording = \"false\""

# Remove nohotkeyprofile and hotkeyprofile folders if they exist

if [ -d "/mnt/SDCARD/RetroArch/hotkeyprofile" ]; then
    rm -rf "/mnt/SDCARD/RetroArch/hotkeyprofile"
    log_message "Removed /mnt/SDCARD/RetroArch/hotkeyprofile folder"
fi

if [ -d "/mnt/SDCARD/RetroArch/nohotkeyprofile" ]; then
    rm -rf "/mnt/SDCARD/RetroArch/nohotkeyprofile"
    log_message "Removed /mnt/SDCARD/RetroArch/nohotkeyprofile folder"
fi

# Check if the update was successful
if [ $? -eq 0 ]; then
    log_message "Upgrade to version $TARGET_VERSION completed successfully"
    exit 0
else
    log_message "Error: Upgrade to version $TARGET_VERSION failed"
    exit 1
fi

# Changes made this update
#content_show_add = "false"
#content_show_explore = "false"
#content_show_favorites = "false"
#content_show_playlists = "false"
#core_info_savestate_bypass = "true"
#core_updater_buildbot_assets_url = "http://buildbot.libretro.com/assets/"
#input_enable_hotkey = "rctrl"
#input_exit_emulator = "ctrl"
#input_fps_toggle = "alt"
#input_joypad_driver = "linuxraw"
#input_load_state = "tab"
#input_menu_toggle = "shift"
#input_menu_toggle_btn = "9"
#input_player1_l_x_minus_axis = "-0"
#input_player1_l_x_plus_axis = "+0"
#input_player1_l_y_minus_axis = "-1"
#input_player1_l_y_plus_axis = "+1"
#input_quit_gamepad_combo = "0"
#input_save_state = "backspace"
#input_screenshot = "space"
#input_shader_toggle = "up"
#input_state_slot_decrease = "left"
#input_state_slot_increase = "right"
#input_toggle_slowmotion = "e"
#menu_show_core_updater = "false"
#menu_unified_controls = "true"
#notification_show_autoconfig = "false"
#notification_show_save_state = "true"
#quick_menu_show_add_to_favorites = "false"
#quick_menu_show_core_options_flush = "true"
#quick_menu_show_download_thumbnails = "false"
#quick_menu_show_reset_core_association = "false"
#quick_menu_show_savestate_submenu = "false"
#quick_menu_show_set_core_association = "false"
#quick_menu_show_start_recording = "false"
#quick_menu_show_start_streaming = "false"
#remap_save_on_exit = "true"
#settings_show_accessibility = "false"
#settings_show_playlists = "false"
#settings_show_power_management = "false"
#settings_show_recording = "false"

