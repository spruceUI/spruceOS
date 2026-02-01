#!/bin/sh

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/rumble.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"


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

trigger_device_sleep() {
    echo -n mem >/sys/power/state
}


WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"
device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"

    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}


device_exit_sleep(){
    clear_wake_alarm $WAKE_ALARM_PATH
}

get_current_volume() {
    amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%'
}


set_volume() {
    new_vol="${1:-0}" # default to mute if no value supplied
    SAVE_TO_CONFIG="${2:-true}"   # Optional 2nd arg, defaults to true
    scaled=$(( new_vol * 255 / 20 ))
    amixer set 'Soft Volume Master' "$scaled"
    if [ "$SAVE_TO_CONFIG" = true ]; then
        current_volume=$(jq -r '.vol' "$SYSTEM_JSON")

        if [ "$current_volume" -ne "$new_vol" ]; then
            save_volume_to_config_file "$new_vol"
            sed -i "s/\"vol\":[[:space:]]*[0-9]\+/\"vol\": $new_vol/" /mnt/UDISK/system.json
            if ! pgrep MainUI >/dev/null; then
                /usr/trimui/osd/show_volume_msg.sh "$new_vol" &
            fi
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

run_mixer_watchdog() {
    log_message "*** nothing to do for run_mixer_watchdog" -v
}

new_execution_loop() {
    log_message "*** nothing to do for new_execution_loop" -v
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
    launch_common_startup_watchdogs_v2 "false"
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


init_gpio_a133p() {
    log_message "Missing init_gpio_a133p method for TrimUI A133P device"
}

runtime_mounts_a133p() {
	# PortMaster ports location
    mkdir -p /mnt/SDCARD/Roms/PORTS/ports/ 
    mount --bind /mnt/SDCARD/Roms/PORTS/ /mnt/SDCARD/Roms/PORTS/ports/

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


    (
        syslogd -S
        hwclock -s -u
        /etc/bluetooth/bluetoothd start
    ) &


    run_trimui_blobs "trimui_inputd trimui_scened trimui_btmanager hardwareservice musicserver"
}

set_event_arg_for_idlemon() {
    log_message "nothing to do" -v
}


set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

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

# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}

device_prepare_for_ports_run() {
    log_message "device_prepare_for_ports_run uneeded on this device" -v
}

device_cleanup_after_ports_run() {
    log_message "device_cleanup_after_ports_run uneeded on this device" -v
}

set_backlight() {
    val="$1"


    # Clamp input to 1–10
    [ "$val" -lt 1 ] && val=1
    [ "$val" -gt 10 ] && val=10


    # Convert 1–10 → 1–255
    val_255=$(( (val - 1) * 254 / 9 + 1 ))


    "$DEVICE_PYTHON3_PATH" - <<EOF
import os, fcntl, ctypes, sys, traceback


try:
    DISP_LCD_SET_BRIGHTNESS = 0x102
    val = int("$val_255")

    print(f"[PY] Brightness value: {val}", file=sys.stderr)

    if not os.path.exists("/dev/disp"):
        print("[PY][ERR] /dev/disp does not exist", file=sys.stderr)
        sys.exit(1)

    fd = os.open("/dev/disp", os.O_RDWR)

    param = (ctypes.c_ulong * 4)(0, val, 0, 0)

    fcntl.ioctl(fd, DISP_LCD_SET_BRIGHTNESS, param)

    os.close(fd)

except Exception as e:
    print("[PY][EXCEPTION]", e, file=sys.stderr)
    traceback.print_exc()
EOF

    tmp=$(mktemp)
    jq ".backlight = $val" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON"
}

current_backlight() {
    jq -r '.backlight' "$SYSTEM_JSON"
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

