#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"

get_sftp_service_name() {
    echo "sftpgo"
}

get_ssh_service_name() {
    echo "sshd"
}

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/gkd-pixel2-system.json"
}

get_python_path() {
    echo "/mnt/SDCARD/spruce/pixel2/bin/python"
}

setup_for_retroarch_and_get_bin_location(){
    RA_DIR="/mnt/SDCARD/RetroArch"
    export RA_BIN="retroarch.Pixel2"
    export CORE_DIR="$RA_DIR/.retroarch/cores64"

    if [ "$CORE" = "uae4arm" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
	elif [ "$CORE" = "easyrpg" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
	elif [ "$CORE" = "yabasanshiro" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
	fi

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

    echo "$RA_BIN"
}

get_ra_cfg_location(){
	echo "/mnt/SDCARD/RetroArch/retroarch.cfg"
}

get_spruce_ra_cfg_location() {
    echo "/mnt/SDCARD/RetroArch/platform/retroarch-Pixel2.cfg"
}

device_init() {
    touch /mnt/SDCARD/spruce/pixel2/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/pixel2/bin/python /mnt/SDCARD/spruce/pixel2/bin/MainUI
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e /dev/input/event2"
}

perform_fw_check(){
    log_message "There is only a single firmware, it was never updated" -v
}

check_if_fw_needs_update() {
    log_message "There is only a single firmware, it was never updated" -v
}

enable_or_disable_rgb() {
    log_message "rgb led not supported on this" -v
}

prepare_for_pyui_launch(){
    set_performance
    echo "performance" > /sys/class/devfreq/dmc/governor
    (
        # SDL2 takes forever, let it initialize before going to powersave
        sleep 5
        set_smart
        unlock_governor 2>/dev/null
    ) &
}

post_pyui_exit(){
    log_message "This doesn't need to do anything when exitting pyui" -v
}

launch_startup_watchdogs(){
    launch_common_startup_watchdogs_v2 "false"
}

# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}

get_volume_level() {
    VALUE=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '(?<=\s)(\d*)(?=\%)' | head -n1)

    logger "Volume value: $VALUE"
    case $VALUE in
        $SYSTEM_VOLUME_0) echo 0 ;;
        $SYSTEM_VOLUME_1) echo 1 ;;
        $SYSTEM_VOLUME_2) echo 2 ;;
        $SYSTEM_VOLUME_3) echo 3 ;;
        $SYSTEM_VOLUME_4) echo 4 ;;
        $SYSTEM_VOLUME_5) echo 5 ;;
        $SYSTEM_VOLUME_6) echo 6 ;;
        $SYSTEM_VOLUME_7) echo 7 ;;
        $SYSTEM_VOLUME_8) echo 8 ;;
        $SYSTEM_VOLUME_9) echo 9 ;;
        $SYSTEM_VOLUME_10) echo 10 ;;
        $SYSTEM_VOLUME_11) echo 11 ;;
        $SYSTEM_VOLUME_12) echo 12 ;;
        $SYSTEM_VOLUME_13) echo 13 ;;
        $SYSTEM_VOLUME_14) echo 14 ;;
        $SYSTEM_VOLUME_15) echo 15 ;;
        $SYSTEM_VOLUME_16) echo 16 ;;
        $SYSTEM_VOLUME_17) echo 17 ;;
        $SYSTEM_VOLUME_18) echo 18 ;;
        $SYSTEM_VOLUME_19) echo 19 ;;
        $SYSTEM_VOLUME_20) echo 20 ;;
        *) echo 10 ;;
    esac
}

set_volume() {
    VOL_VAL="${1:-0}" # default to mute if no value supplied
    SAVE_TO_CONFIG="${2:-true}" # Optional 2nd arg, defaults to true

    logger "Setting volume to $VOL_VAL"
    if [ $VOL_VAL -lt 0 ]; then
        VOL_VAL=0
    elif [ $VOL_VAL -gt 20 ]; then
        VOL_VAL=20
    fi

    # Set volume
    SYSTEM_VOL=$(map_mainui_volume_to_system_value "$VOL_VAL")
    pactl -- set-sink-volume @DEFAULT_SINK@ ${SYSTEM_VOL}%

    if [ "$SAVE_TO_CONFIG" = true ]; then
        # Update Config file
        sed -i "s/\"vol\":\s*\([0-9]*\)/\"vol\": $VOL_VAL/" "$SYSTEM_JSON"
    fi
}

volume_down() {
    VALUE=$(get_volume_level)
    VALUE=$((${VALUE} - 1))
    set_volume "$VALUE"
}

volume_up() {
    VALUE=$(get_volume_level)
    VALUE=$((${VALUE} + 1))
    set_volume "$VALUE"
}

# Map the MainUI Volume level to System Value
map_mainui_volume_to_system_value() {
    case $1 in
        0) echo $SYSTEM_VOLUME_0 ;;
        1) echo $SYSTEM_VOLUME_1 ;;
        2) echo $SYSTEM_VOLUME_2 ;;
        3) echo $SYSTEM_VOLUME_3 ;;
        4) echo $SYSTEM_VOLUME_4 ;;
        5) echo $SYSTEM_VOLUME_5 ;;
        6) echo $SYSTEM_VOLUME_6 ;;
        7) echo $SYSTEM_VOLUME_7 ;;
        8) echo $SYSTEM_VOLUME_8 ;;
        9) echo $SYSTEM_VOLUME_9 ;;
        10) echo $SYSTEM_VOLUME_10 ;;
        11) echo $SYSTEM_VOLUME_11 ;;
        12) echo $SYSTEM_VOLUME_12 ;;
        13) echo $SYSTEM_VOLUME_13 ;;
        14) echo $SYSTEM_VOLUME_14 ;;
        15) echo $SYSTEM_VOLUME_15 ;;
        16) echo $SYSTEM_VOLUME_16 ;;
        17) echo $SYSTEM_VOLUME_17 ;;
        18) echo $SYSTEM_VOLUME_18 ;;
        19) echo $SYSTEM_VOLUME_19 ;;
        20) echo $SYSTEM_VOLUME_20 ;;
        *) echo $SYSTEM_VOLUME_10 ;;
    esac
}

WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"

    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    /usr/lib/systemd/systemd-sleep suspend
}

device_exit_sleep() {
    echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
}

device_lid_open(){
    # device has no lid so it's always open
    return 1
}

take_screenshot() {
    screenshot_path="$1"
    /mnt/SDCARD/spruce/pixel2/bin/grim -o DSI-1 "${screenshot_path}"
}

vibrate() {
    duration=50
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

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

    case "$intensity" in
            "Weak")   intensity=0x2000 ;;
            "Medium") intensity=0x8000 ;;
            "Strong") intensity=0xFFFF ;;
    esac

    /mnt/SDCARD/spruce/pixel2/bin/rumble $EVENT_PATH_READ_INPUTS_SPRUCE $intensity $duration
}

current_backlight() {
    jq -r '.backlight' "$SYSTEM_JSON"
}

# Map the MainUI Volume level to System Value
map_mainui_brightness_to_system_value() {
    case $1 in
        0) echo $SYSTEM_BRIGHTNESS_0 ;;
        1) echo $SYSTEM_BRIGHTNESS_1 ;;
        2) echo $SYSTEM_BRIGHTNESS_2 ;;
        3) echo $SYSTEM_BRIGHTNESS_3 ;;
        4) echo $SYSTEM_BRIGHTNESS_4 ;;
        5) echo $SYSTEM_BRIGHTNESS_5 ;;
        6) echo $SYSTEM_BRIGHTNESS_6 ;;
        7) echo $SYSTEM_BRIGHTNESS_7 ;;
        8) echo $SYSTEM_BRIGHTNESS_8 ;;
        9) echo $SYSTEM_BRIGHTNESS_9 ;;
        10) echo $SYSTEM_BRIGHTNESS_10 ;;
        *) echo $SYSTEM_BRIGHTNESS_5 ;;
    esac
}

set_backlight() {
    new_bl="$1"
    sys_bl=$(map_mainui_brightness_to_system_value "$new_bl")
    if (( $new_bl >= 0 )) && (( $new_bl <= 10 )); then
        echo $sys_bl > $DEVICE_BRIGHTNESS_PATH
        sed -i "s/\"backlight\":\s*\([0-9]\|10\)/\"backlight\": $new_bl/" "$SYSTEM_JSON"
    fi
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
    EVENT_ARG="-e /dev/input/event2"
}

send_virtual_key_L3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        sleep 0.1
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP
}

send_menu_button_to_retroarch() {
    if pgrep "retroarch.Pixel2" >/dev/null; then
        echo "MENU_TOGGLE" | /mnt/SDCARD/spruce/pixel2/bin/netcat -u -w0.1 127.0.0.1 55355
    elif pgrep -f "PPSSPPSDL_Pixel2" >/dev/null; then
        send_virtual_key_L3
    fi
    # PICO8 has no in-game menu and
    # NDS has 2 in-game menus that are activated by hotkeys with menu button short tap
}

set_default_ra_hotkeys() {
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-Flip.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    # Update RetroArch config with default values
    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"5\"" \
        "input_exit_emulator_btn = \"1\"" \
        "input_fps_toggle_btn = \"3\"" \
        "input_load_state_btn = \"9\"" \
        "input_menu_toggle = \"escape\"" \
        "input_menu_toggle_btn = \"nul\"" \
        "input_quit_gamepad_combo = \"4\"" \
        "input_save_state_btn = \"10\"" \
        "input_screenshot_btn = \"0\"" \
        "input_shader_toggle_btn = \"11\"" \
        "input_state_slot_decrease_btn = \"13\"" \
        "input_state_slot_increase_btn = \"14\"" \
        "input_toggle_slowmotion_axis = \"+4\"" \
        "input_toggle_fast_forward_axis = \"+5\""

}