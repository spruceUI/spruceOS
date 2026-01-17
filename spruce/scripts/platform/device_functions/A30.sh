#!/bin/sh

export EVENT_PATH_JOYPAD="/dev/input/event4"
export EVENT_PATH_KEYBOARD="/dev/input/event3"

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common32bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/flip_a30_brightness.sh"

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/a30-system.json"
}

set_overclock() {
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online 01234567   # bring all up before potentially offlining cpu0
        cores_online "$DEVICE_MAX_CORES_ONLINE"
        unlock_governor 2>/dev/null
        /mnt/SDCARD/spruce/bin/setcpu/utils "performance" 4 1512 384 1080 1
        lock_governor 2>/dev/null
        log_message "CPU Mode now locked to OVERCLOCK" -v
        flag_remove "setting_cpu"
    fi
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
    if [ "$intensity" = "Strong" ]; then    # 100% duty cycle
        echo "$duration" >/sys/devices/virtual/timed_output/vibrator/enable
    elif [ "$intensity" = "Medium" ]; then  # 83% duty cycle
        timer=0
        while [ $timer -lt $duration ]; do
            echo 5 >/sys/devices/virtual/timed_output/vibrator/enable
            sleep 0.006
            timer=$(($timer + 6))
        done &
    elif [ "$intensity" = "Weak" ]; then    # 75% duty cycle
        timer=0
        while [ $timer -lt $duration ]; do
            echo 3 >/sys/devices/virtual/timed_output/vibrator/enable
            sleep 0.004
            timer=$(($timer + 4))
        done &
    else
        log_message "this is where I'd put my vibration... IF I HAD ONE"
    fi

    echo 0 >/sys/devices/virtual/timed_output/vibrator/enable

}


rgb_led() {
    [ -n "$6" ] && echo "$6" > "$LED_PATH/trigger"
    return 0
}

# used in principal.sh
enable_or_disable_rgb() {
    log_message "No RGB on A30" -v
}

enter_sleep() {
    log_message "Entering sleep."
    echo -n mem >/sys/power/state
}

get_current_volume() {
    amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%'
}

# Not updated to match other devices yet, takes raw value
set_volume() {
    amixer set 'Soft Volume Master' "$new_vol" 
}

run_mixer_watchdog() {
    log_message "Not needed for A30: run_mixer_watchdog" -v
}

new_execution_loop() {
    log_message "Not needed for A30: new_execution_loop" -v
}

setup_for_retroarch_and_get_bin_location(){
	RA_DIR="/mnt/SDCARD/RetroArch"
    export CORE_DIR="$RA_DIR/.retroarch/cores"

	if [ "$use_igm" = "False" ] || [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
		export RA_BIN="retroarch.A30"
	else
		export RA_BIN="ra32.miyoo"
	fi


	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

    echo "$RA_BIN"

}


# TODO this is actually dependent on which emulator is being used
# and cannot be generically done
# Send L3 and R3 press event, this would toggle in-game and pause in RA
# or toggle in-game menu in PPSSPP
send_virtual_key_L3R3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        echo $B_R3 1 # R3 down
        sleep 0.1
        echo $B_R3 0 # R3 up
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP
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
    if pgrep "ra32.miyoo" >/dev/null; then
        send_virtual_key_L3
    elif pgrep -f "retroarch" >/dev/null; then
        send_virtual_key_L3R3
    elif pgrep -f "PPSSPPSDL" >/dev/null; then
        send_virtual_key_L3
    fi
    # PICO8 has no in-game menu and
    # NDS has 2 in-game menus that are activated by hotkeys with menu button short tap
}

prepare_for_pyui_launch(){
    killall -q -USR2 joystickinput  # this allows joystick to be used as DPAD in MainUI
}

post_pyui_exit(){
    killall -q -USR1 joystickinput   # return the stick to being a stick
}

launch_startup_watchdogs(){
    launch_common_startup_watchdogs
}

perform_fw_check(){
    FW_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/firmwareupdate.png"

    # A30's firmware check
    VERSION=$(cat /usr/miyoo/version)
    if [ "$VERSION" -lt 20240713100458 ]; then
        log_message "Detected firmware version $VERSION, turning off wifi and suggesting update"
        sed -i 's|"wifi":	1|"wifi":	0|g' "$SYSTEM_JSON"
        display_image_and_text "$FW_ICON" 35 25 "Visit the App section from the main menu to update your firmware to the latest version. It fixes the A30's Wi-Fi issues!" 75
        sleep 5
    fi

}


# Should the above be merged into here?
check_if_fw_needs_update() {
    VERSION="$(cat /usr/miyoo/version)"
    [ "$VERSION" -ge "$TARGET_FW_VERSION" ] && echo "false" || echo "true"
}

take_screenshot() {
    screenshot_path="$1"
    /mnt/SDCARD/spruce/a30/screenshot.sh "$screenshot_path"
}

device_specific_wake_from_sleep() {
    log_message "nothing to do" -v
}


runtime_mounts_A30() {
    mkdir -p /var/lib/alsa
    mkdir -p /mnt/SDCARD/spruce/dummy
    mount -o bind "/mnt/SDCARD/miyoo/var/lib" /var/lib &
    mount -o bind /mnt/SDCARD/miyoo/lib /usr/miyoo/lib &
    mount -o bind /mnt/SDCARD/miyoo/res/skin /usr/miyoo/res/skin &
    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    /mnt/SDCARD/spruce/a30/sdl2/bind.sh &
    wait
    touch /mnt/SDCARD/spruce/bin/python/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/bin/python/bin/python3.10 /mnt/SDCARD/spruce/bin/python/bin/MainUI
}

device_init() {
    runtime_mounts_A30

    echo L,L2,R,R2,X,A,B,Y > /sys/module/gpio_keys_polled/parameters/button_config
    nice -n -18 sh -c '/etc/init.d/sysntpd stop && /etc/init.d/ntpd stop' > /dev/null 2>&1  # Stop NTPD
    killall MtpDaemon 2>/dev/null
    killall -9 main ### SUPER important in preventing .tmp_update suicide
    alsactl nrestore &

    # Restore and monitor brightness
    TMP_BACKLIGHT_PATH=/mnt/SDCARD/Saves/spruce/tmp_backlight
    if [ -f "$TMP_BACKLIGHT_PATH" ]; then
        BRIGHTNESS="$(cat $TMP_BACKLIGHT_PATH)"
        # only set non zero brightness value
        if [ "$BRIGHTNESS" -ne 0 ]; then 
            echo "$BRIGHTNESS" > /sys/devices/virtual/disp/disp/attr/lcdbl
        fi
    else
        echo 72 > /sys/devices/virtual/disp/disp/attr/lcdbl # = backlight setting at 5
    fi

    # listen hotkeys for brightness adjustment, volume buttons and power button
    # What is being changed later that prevents this from running with the other watchdogs?
    /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh &

    # rename ttyS0 to ttyS2 so that PPSSPP cannot read the joystick raw data
    mv /dev/ttyS0 /dev/ttyS2

    # create virtual joypad from keyboard input, it should create /dev/input/event4 system file
    cd "/mnt/SDCARD/spruce/bin"
    ./joypad $EVENT_PATH_KEYBOARD &
    /mnt/SDCARD/spruce/scripts/platform/device_functions/utils/a30/autoReloadCalibration.sh &
}

set_event_arg_for_idlemon() {
    log_message "nothing to do" -v
}


set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    # Update RetroArch config with default values

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

}


reset_playback_pack() {
    log_message "reset_playback_pack Uneeded on this device" -v
}

save_volume_to_config_file() {
    VOLUME_LV=$1
    sed -i "s/\"vol\":\s*\([0-9]*\)/\"vol\": $VOLUME_LV/" "$SYSTEM_JSON"
}

_set_volume() {
    VOLUME_LV="$1"
    VOLUME_RAW=$(( (VOLUME_LV * 255 + 10) / 20 ))
    log_message "Setting volume to ${VOLUME_RAW}"
    amixer set 'Soft Volume Master' $VOLUME_RAW > /dev/null
    save_volume_to_config_file "$VOLUME_LV"

}

volume_down() {
    VOLUME_LV=$(get_volume_level)
    # if value greater than zero
    if [ $VOLUME_LV -gt 0 ] ; then
        VOLUME_LV=$((VOLUME_LV-1))
        _set_volume "$VOLUME_LV"
    fi
}

volume_up() {
    VOLUME_LV=$(get_volume_level)
    # if value less than 20
    if [ $VOLUME_LV -lt 20 ] ; then
        VOLUME_LV=$((VOLUME_LV+1))
        _set_volume "$VOLUME_LV"
    fi
}

get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON"
}


# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}
