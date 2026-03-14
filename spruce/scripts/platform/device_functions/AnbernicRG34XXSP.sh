#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/rumble.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"

get_config_path() {
    echo "$SYSTEM_JSON"
}

###############################################################################
WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

trigger_device_sleep() {
    echo -n mem >/sys/power/state
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"

    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

device_exit_sleep() {
    echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
}

device_lid_sensor_ready() {
    [ -e "/sys/class/power_supply/axp2202-battery/hallkey" ]
}

device_lid_open() {
    head -c 1 "/sys/class/power_supply/axp2202-battery/hallkey" 2>/dev/null || echo "1"
}

# Will miyoo ones work?
setup_for_retroarch_and_get_bin_location(){
	#RA_DIR="/mnt/vendor/deep/retro"
    #export RA_BIN="retroarch"
    #export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"


    /mnt/SDCARD/RetroArch/.config/retroarch/autoconfig/sdl2
	RA_DIR="/mnt/SDCARD/RetroArch"
	export RA_BIN="ra64.universal"
    export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores64"


	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi
   
   
    echo "$RA_BIN"
}


send_virtual_key_L3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down 
        sleep 0.1
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_READ_INPUTS_SPRUCE
}

launch_startup_watchdogs(){
    log_message "No watchdogs tested on 34xxsp yet"
}

perform_fw_check(){
    log_message "Miyoo Flip can't perform firmware check?" -v
}

close_ppsspp_menu() {

    if pgrep -f "PPSSPPSDL" >/dev/null; then
        log_message "homebutton_watchdog.sh: Closing PPSSPP menu."
        # use sendevent to send SELECT + R1 combo buttons to PPSSPP
        {
            echo $B_RIGHT 1  
            echo $B_RIGHT 0  
            echo $B_A 1  
            echo $B_A 0  
        } > /tmp/ppsspp_events.txt


        # run sendevent in a fully detached subshell
        (
            sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP < /tmp/ppsspp_events.txt
        ) < /dev/null > /dev/null 2>&1 &

        sleep 0.5
    fi
}

take_screenshot() {
    log_message "Unable to doso on 34xxsp currently"
}

runtime_mounts_anbernic_34xxsp() {

    #mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    #mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    #mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &

    ln -s /usr/bin/python3 /usr/bin/MainUI

    mount --bind /mnt/vendor/deep/retro/retroarch-1.20 /mnt/sdcard/RetroArch/retroarch
}

device_init() {
    runtime_mounts_anbernic_34xxsp

    /mnt/SDCARD/anbernic_adbd/run_adbd.sh &
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e /dev/input/event1" # is this right?
}

set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

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

new_execution_loop() {
    log_message "new_execution_loop Uneeded on this device" -v
}

# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}

device_system_handles_sdcard_unmount() {
    # return 0 = true
    # return non-zero = false
    return 0
}

set_volume() {
    new_vol="${1:-0}"        # default to mute
    SAVE_TO_CONFIG="${2:-true}"

    # Clamp 0–20
    [ "$new_vol" -lt 0 ] && new_vol=0
    [ "$new_vol" -gt 20 ] && new_vol=20

    # Map 0–20 -> 0–31 (rounded)
    system_volume=$(( (new_vol * 31 + 10) / 20 ))

    amixer -q set 'lineout volume' "$system_volume"

    if [ "$SAVE_TO_CONFIG" = true ]; then
        current_volume=$(jq -r '.vol' "$SYSTEM_JSON")

        if [ "$current_volume" -ne "$new_vol" ]; then
            save_volume_to_config_file "$new_vol"

            sed 's/"vol":[[:space:]]*[0-9]\+/"vol": '"$new_vol"'/' \
                "$SYSTEM_JSON" > "$SYSTEM_JSON.tmp" && mv "$SYSTEM_JSON.tmp" "$SYSTEM_JSON"
        fi
    fi
}

set_volume_delta() {
    delta="$1"

    current=$(get_volume_level)
    [ -z "$current" ] && current=0

    new=$((current + delta))

    # Clamp 0–20
    [ "$new" -lt 0 ] && new=0
    [ "$new" -gt 20 ] && new=20

    set_volume "$new"
}

volume_up() {
    set_volume_delta 1
}

volume_down() {
    set_volume_delta -1
}

get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON"
}
