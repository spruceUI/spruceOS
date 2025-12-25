#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

get_python_path() {
    echo "/mnt/SDCARD/spruce/bin/python/bin/python3.10" 
}

export_ld_library_path() {
    export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/miyoomini/lib/:/config/lib/:/customer/lib:/mnt/SDCARD/miyoo/lib"
}

export_spruce_etc_dir() {
    export SPRUCE_ETC_DIR="/mnt/SDCARD/spruce/miyoomini/etc"
}

get_sd_card_path() {
    echo "/mnt/SDCARD"
}

get_config_path() {
    echo "/mnt/SDCARD/Saves/mini-flip-system.json"
}

###############################################################################
# CPU CONTROLS #
################

# Usage:
#   cores_online            -> defaults to cores 0-3
#   cores_online "0135"     -> online cores 0,1,3,5; offline others
cores_online() {
    log_message "cores online not implemented for miyoo_mini" -v
}


set_smart() {
    echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
}

set_performance() {
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
}

set_overclock() {
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
}

vibrate() {
    log_message "Vibration not enabled for miyoo mini" -v
}

display_kill() {
    log_message "Only PyUI is supported on Miyoo Mini for display functionality" -v
}

display() {
    log_message "Only PyUI is supported on Miyoo Mini for display functionality" -v
}

rgb_led() {
    log_message "rgb led not supported on miyoo mini"
}

enable_or_disable_rgb() {
    log_message "rgb led not supported on miyoo mini"
}

restart_wifi() {
    log_message "Intentionally do not let spruce modify wifi" -v
}

get_qr_bin_path() {
    echo "/mnt/SDCARD/spruce/bin/qrencode"
}

set_path_variable() {
    export PATH="/mnt/SDCARD/spruce/miyoomini/bin:/mnt/SDCARD/spruce/bin:$PATH"
}

enter_sleep() {
    log_message "Keymon handles sleep, not spruce" -v
}

get_current_volume() {
    log_message "Intentionally do not let spruce modify volume" -v
}

set_volume() {
    log_message "Intentionally do not let spruce modify volume" -v
}


reset_playback_pack() {
    log_message "Intentionally do not let spruce modify audio, let keymon" -v
}

set_playback_path() {
    log_message "Intentionally do not let spruce modify audio, let keymon" -v
}

run_mixer_watchdog() {
    log_message "Intentionally do not let spruce modify audio, let keymon" -v
}

new_execution_loop() {
    pidof audioserver >/dev/null || audioserver &
}

get_spruce_ra_cfg_location() {
    echo "/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
}

get_ra_cfg_location(){
	echo "/mnt/SDCARD/RetroArch/.retroarch/retroarch.cfg"
}

setup_for_retroarch_and_get_bin_location(){
    export CORE_DIR="/mnt/SDCARD/spruce/miyoomini/RetroArch/.retroarch/cores"
    export RA_BIN="retroarch"

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

    echo "$RA_BIN"
}

send_menu_button_to_retroarch() {
    if pgrep -f "retroarch" >/dev/null; then
        ra_network_command MENU_TOGGLE
    fi
}

prepare_for_pyui_launch(){
    set_performance
}

post_pyui_exit(){
    log_message "MiyooMini doesn't need to do anything after pyui exit (should we call freemma?)" -v
}

launch_startup_watchdogs(){
    ${SCRIPTS_DIR}/homebutton_watchdog.sh &
}

perform_fw_check(){
    log_message "No Fw Check for MiyooMini" -v
}


# Should the above be merged into here?
check_if_fw_needs_update() {
    log_message "No Fw Check for MiyooMini" -v
}

take_screenshot() {
    screenshot_path="$1"
    screenshot.sh "$screenshot_path"
}

get_sftp_service_name() {
    echo "sftp-server"
}

device_specific_wake_from_sleep() {
    log_message "MiyooMini has no specific device wake from sleep needed" -v
}

device_init() {
    log_message "No initialization needed for miyoo mini (handled via .tmp_update)" -v   
}

# This doesn't seem right for all platforms, needs review
set_event_arg() {
    log_message "TODO event arg for miyoo mini?" -v
}

set_dark_httpd_dir() {
    DARKHTTPD_DIR=/mnt/SDCARD/spruce/bin/darkhttpd
}

# Why can't these just all come off the path? / Why do they need special LD LIBRARY PATHS?

set_SMB_DIR(){
    SMB_DIR=/mnt/SDCARD/spruce/bin/Samba
}

set_LD_LIBRARY_PATH_FOR_SAMBA(){
    log_message "No LD Library Path manip needed for samba on miyoo mini" -v   
}

set_SFTPGO_DIR() {
    SFTPGO_DIR="/mnt/SDCARD/spruce/bin/SFTPGo"
}

set_syncthing_ST_BIN() {
    ST_BIN=$SYNCTHING_DIR/bin/syncthing
}

set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."
    # Are these right for miyoo mini?
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