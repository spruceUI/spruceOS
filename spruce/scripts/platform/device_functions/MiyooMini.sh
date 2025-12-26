#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common32bit.sh"


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
    duration=50

    # Parse arguments in any order
    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    echo out > /sys/class/gpio/gpio48/direction
    sleep "$duration"
    echo 1 > /sys/class/gpio/gpio48/value
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
    echo "/mnt/SDCARD/RetroArch/platform/retroarch-MiyooMini.cfg"
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
    ${SCRIPTS_DIR}/buttons_watchdog.sh &
    ${SCRIPTS_DIR}/applySetting/idlemon_mm.sh &
    ${SCRIPTS_DIR}/low_power_warning.sh &
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

volume_down() {
    log_message "Volume is handled via keymon" -v
}

volume_up() {
    log_message "Volume is handled via keymon" -v
}

get_volume_level() {
    log_message "Volume is handled via keymon" -v
    echo "0"
}

current_backlight() {
    jq -r '.backlight' "$SYSTEM_JSON"
}

set_backlight() {
    local value="$1"

    # Clamp between 0–10
    [ "$value" -lt 0 ] && value=0
    [ "$value" -gt 10 ] && value=10

    sed -i "s/\"backlight\": *[0-9][0-9]*/\"backlight\": $value/" "$SYSTEM_JSON"
    # Should we get this from path or always from PyUI?
    /mnt/SDCARD/App/PyUI/main-ui/devices/miyoo/mini/set_shared_memory 1 "$value"
}

brightness_down() {
    local backlight
    backlight=$(current_backlight)
    set_backlight $((backlight - 1))
}

brightness_up() {
    local backlight
    backlight=$(current_backlight)
    set_backlight $((backlight + 1))
}

set_event_arg() {
    EVENT_ARG="-e /dev/input/event0"
}

device_get_charging_status() {
    charging=$( /customer/app/axp_test | grep -o '"charging":[0-9]*' | sed 's/"charging"://' )
    if [ "$charging" -eq 0 ]; then
        echo "Discharging"
    else
        echo "Charging"
    fi
}

device_get_battery_percent() {
    battery=$( /customer/app/axp_test | grep -o '"battery":[0-9]*' | sed 's/"battery"://' )
    echo "$battery"
}