#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/common32bit.sh"


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
    log_message "TODO: spruce breaks RA cfg so return fake value from get_ra_cfg_location"
    touch /tmp/ignore.txt
	echo "/tmp/ignore.txt"
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

set_default_ra_hotkeys() {
    log_message "TODO: set_default_ra_hotkeys"
}


device_specific_wake_from_sleep() {
    log_message "MiyooMini has no specific device wake from sleep needed" -v
}
