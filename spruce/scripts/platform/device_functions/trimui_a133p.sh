#!/bin/sh

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/rumble.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"

get_sd_card_path() {
    echo "/mnt/SDCARD"
}


###############################################################################

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
    rumble_gpio "$@"
}

rgb_led() {
    rgb_led_trimui "$@"
}


# used in principal.sh
enable_or_disable_rgb() {
    enable_or_disable_rgb_trimui "$@"
}

enter_sleep() {
    log_message "Entering sleep."
    echo -n mem >/sys/power/state
}


get_current_volume() {
    amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%'
}

set_volume() {
    amixer set 'Soft Volume Master' "$new_vol"
}

reset_playback_pack() {
    #TODO I think this is wrong
    log_message "*** audioFunctions.sh: reset playback path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    system_json_volume=$(cat $SYSTEM_JSON | grep -o '"vol":\s*[0-9]*' | grep -o [0-9]*)
    current_vol_name="SYSTEM_VOLUME_$system_json_volume"
    
    eval vol_value=\$$current_vol_name
    
    amixer sset 'SPK' "$vol_value%" > /dev/null
    amixer cset name='Playback Path' 0 > /dev/null
    amixer cset name='Playback Path' "$current_path" > /dev/null
}


set_playback_path() {
    #TODO I think this is wrong
    volume_lv=$(amixer cget name='SPK Volume' | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    log_message "*** audioFunctions.sh: Volume level: $volume_lv" -v

    jack_status=$(cat /sys/class/gpio/gpio150/value) # 0 connected, 1 disconnected
    log_message "*** audioFunctions.sh: Jack status: $jack_status" -v

    # 0 OFF, 2 SPK, 3 HP
    playback_path=$([ $jack_status -eq 1 ] && echo 2 || echo 3)
    [ "$volume_lv" = 0 ] && [ "$playback_path" = 2 ] && playback_path=0
    log_message "*** audioFunctions.sh: Playback path: $playback_path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)

    amixer cset name='Playback Path' "$playback_path" > /dev/null
    # if coming off mute, ensure that there's a change so that volume doesn't spike
    ( (( current_path == 0 )) || (( current_path != playback_path )) ) && [ ! "$playback_path" = 0 ] \
      && amixer sset 'SPK' 1% > /dev/null && amixer sset 'SPK' "$volume_lv%" > /dev/null
}


run_mixer_watchdog() {
    log_message "*** nothing to do for run_mixer_watchdog" -v
}

new_execution_loop() {
    log_message "*** nothing to do for new_execution_loop" -v
}

get_ra_cfg_location(){
	echo "/mnt/SDCARD/RetroArch/retroarch.cfg"
}

setup_for_retroarch_and_get_bin_location(){
    setup_for_retroarch_and_get_bin_location_trimui
}


prepare_for_pyui_launch(){
    rm -f /tmp/trimui_inputd/input_no_dpad
    rm -f /tmp/trimui_inputd/input_dpad_to_joystick
}


post_pyui_exit(){
    # Should we touch input_no_dpad and input_dpad_to_joystick?
    log_message "*** nothing to do for post_pyui_exit" -v
}


launch_startup_watchdogs(){
    launch_common_startup_watchdogs
}



perform_fw_check(){
    log_message "*** nothing to do for perform_fw_check" -v
}

# Should the above be merged into here?
check_if_fw_needs_update() {
    check_if_fw_needs_update_trimui
}

take_screenshot() {
    /mnt/SDCARD/spruce/bin64/fbscreenshot "$1"
}


device_specific_wake_from_sleep() {
    log_message "nothing to do" -v
}


init_gpio_a133p() {
    log_message "Missing init_gpio_a133p method for TrimUI A133P device"
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


device_init_a133p() {
    runtime_mounts_a133p

    export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
    chmod a+x /usr/bin/notify

    init_gpio_a133p

    syslogd -S

    /etc/bluetooth/bluetoothd start

    run_trimui_blobs
    echo -n MENU+SELECT > /tmp/trimui_osd/hotkeyshow
}

set_event_arg() {
    log_message "nothing to do" -v
}


set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-Flip.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."
    #TODO Are these right for TrimUI A133P?
    # Update RetroArch config with default values
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

}

reset_playback_pack() {
    log_message "reset_playback_pack Uneeded on this device" -v
}

set_playback_path() {
    log_message "set_playback_path Uneeded on this device" -v
}

run_mixer_watchdog() {
    log_message "run_mixer_watchdog on this device" -v
}


# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}
