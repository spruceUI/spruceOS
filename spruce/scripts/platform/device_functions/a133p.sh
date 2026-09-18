#!/bin/sh

# Allwinner A133P (sun50iw10p1): the functions that belong to the SoC, not to a
# vendor's userland. Sourced by trimui_a133p.sh (Brick, Brick Pro, Smart Pro,
# which add TrimUI's daemons, OSD and RGB LEDs on top) and by magicx_a133p.sh
# (Mini Zero 28, Zero 40, XU20 V32 on our own Tina base). Anything that needs
# /usr/trimui, trimui_inputd or the TrimUI OSD stays out of this file.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/rumble.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/usb_wifi_dongle.sh"


###############################################################################

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
    rumble_gpio "$@"
}

# The switch is "DIP Switch PH19" on this SoC, exported as gpio243 by each
# device's init_gpio_a133p. Its raw value is the same 1/0 that trimui_scened
# hands scene.sh, so it passes straight through.
#
# The Smart Pro S deliberately has no override for this: it is a different SoC
# and exports no switch GPIO, so it keeps the empty default and skips the
# boot-time apply.
device_get_switch_position() {
    cat /sys/class/gpio/gpio243/value 2>/dev/null
}

trigger_device_sleep() {
    echo -n mem >/sys/power/state
}


WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"
device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"

    wifi_request suspend --wait
    # Whichever driver is the radio comes out for the suspend: a USB dongle's
    # module (it is reloaded by enable_wifi on the way back, after the resume
    # wait usb_wifi_note_sleep arms) or the onboard one.
    usb_wifi_note_sleep
    usb_wifi_tear_down
    usb_wifi_module_loaded xradio_wlan && rmmod xradio_wlan
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}


device_exit_sleep(){
    clear_wake_alarm $WAKE_ALARM_PATH
    # A dongle that was the radio gets a bounded wait to re-enumerate: the host
    # controller is back before the device is.
    if usb_wifi_wait_after_resume; then
        # The dongle is the radio: enable_wifi (device_wifi_power_on) loads its
        # driver and gives it wlan0; loading xradio first would only take the
        # name and have to be unloaded again. Both drivers are out after the
        # suspend, so this has to run whenever the user wants WiFi - the
        # system json is that answer, exactly as at boot.
        wifi_request apply --wait
        return 0
    fi
    modprobe xradio_wlan
    # Sleep turned the radio off without changing the setting, so the setting says whether WiFi was on
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON" 2>/dev/null)" = 1 ]; then
        for _ in 1 2 3 4 5; do
            ip link show wlan0 >/dev/null 2>&1 && break
            sleep 1
        done
    fi
    wifi_request apply --wait
}

get_current_volume() {
    amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%'
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

new_execution_loop() {
    log_message "*** nothing to do for new_execution_loop" -v
}

# Nothing to prepare on a bare board; trimui_a133p.sh overrides this for the
# inputd mode files.
prepare_for_pyui_launch(){
    log_message "*** nothing to do for prepare_for_pyui_launch" -v
}

post_pyui_exit(){
    # Should we touch input_no_dpad and input_dpad_to_joystick?
    log_message "*** nothing to do for post_pyui_exit" -v
}

# No vendor firmware to keep current on a bare board (FW_FILE is empty);
# trimui_a133p.sh overrides this with the TrimUI version check.
check_if_fw_needs_update() {
    echo "false"
}

take_screenshot() {
    screenshot_path="$1"
    /mnt/SDCARD/spruce/bin64/fbscreenshot "$screenshot_path"
}


init_gpio_a133p() {
    log_message "Missing init_gpio_a133p method for this A133P device"
}


set_event_arg_for_idlemon() {
    log_message "nothing to do" -v
}


set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg"

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

    tmp="${SYSTEM_JSON}.tmp.$$"
    jq ".backlight = $val" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON" || rm -f "$tmp"
}


device_system_handles_sdcard_unmount() {
    # return 0 = true
    # return non-zero = false
    return 1 # Brick/SmartPro leaves dirty bit set?
}

# Strict unmount by default (SPR-MED-199). Measured 2026-09-06 with stage 2's
# per-shutdown log: on every TrimUI A133P device the original single umount
# fails on holders the fd-only sweep cannot see - orphaned getevents from the
# power-button watchdog on the Brick, Brick Pro and Smart Pro - and falls back
# to a lazy detach that leaves the FAT dirty flag set. The strict path (cwd,
# exe and mapping holders, a sweep between retries, remount-ro, a holder dump
# on failure) took the card off cleanly on the Smart Pro S, Smart Pro and
# Brick the same night, at a cost of a few seconds.
device_needs_strict_unmount() {
    return 0
}

# Core lookup for the 64-bit RetroArch build. trimui_delegate.sh carries the
# same function for the Smart Pro S; the TrimUI A133P boards take that copy
# (sourced after this file) and a bare board takes this one.
setup_for_retroarch() {

	export CORE_DIR="$RA_DIR/.retroarch/cores64"

	if [ "$CORE" = "uae4arm" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
	elif [ "$CORE" = "easyrpg" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR/lib-trimui:$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
	elif [ "$CORE" = "genesis_plus_gx" ] && [ "$DISPLAY_ASPECT_RATIO" = "16:9" ]; then
		use_gpgx_wide="$(get_config_value '.menuOptions."Emulator Settings".genesisPlusGXWide.selected' "False")"
		[ "$use_gpgx_wide" = "True" ] && CORE="genesis_plus_gx_wide"
	fi

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

    echo "$RA_BIN"

}

# Startup watchdogs for a bare A133P board: the common set, the USB WiFi dongle
# hot-plug loop for a cfg that opted in, and zram. trimui_delegate.sh's override
# (sourced after this file by trimui_a133p.sh) adds the TrimUI volume sync.
launch_startup_watchdogs() {
    launch_common_startup_watchdogs_v2

    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}

    stop_running_watchdog /mnt/SDCARD/spruce/scripts/usb_wifi_watchdog.sh
    if [ -n "$WIFI_USB_MODULES_DIR" ]; then
        /mnt/SDCARD/spruce/scripts/usb_wifi_watchdog.sh &
        pin_cpu "$SYSTEM_CPU" -n usb_wifi_watchdog.sh &
    fi

    /mnt/SDCARD/spruce/scripts/enable_zram.sh &
}

# Backlight steps over set_backlight above; the same trio as trimui_delegate.sh's.
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

# --- WiFi radio -------------------------------------------------------------
# The A133P line's onboard radio is the XR829 (xradio_wlan owns wlan0, loaded
# by the stock init). A supported USB dongle on the USB-C port takes over
# through utils/usb_wifi_dongle.sh: the cfg sets WIFI_USB_MODULES_DIR and
# WIFI_ONBOARD_MODULE, and the contract unloads xradio_wlan, loads the dongle's
# module and names its interface wlan0, so everything downstream (supplicant,
# DHCP, PyUI's status and quality readers) works unchanged. No dongle, or a
# dongle whose module will not load, means the onboard radio exactly as before.
#
# Defined only for a cfg that opted in (the platform cfg is sourced before
# this file). magicx_a133p.sh sources this file too and its cfgs set no dongle
# variables, so that family keeps device.sh's defaults; an unconditional
# definition here would shadow them. (The RGB30 only mentions the A133P file in
# a comment and keeps its own nmcli hooks.)
if [ -n "$WIFI_USB_MODULES_DIR" ]; then

device_wifi_power_on() {
    if usb_wifi_bring_up; then
        return 0
    fi
    # Onboard path. A dongle module left loaded by an earlier session state
    # (the dongle was pulled while WiFi was off, say) goes first so it cannot
    # hold the wlan0 name.
    if ! usb_wifi_dongle_present >/dev/null 2>&1; then
        usb_wifi_tear_down
    fi
    usb_wifi_onboard_restore
}

# "Off" on this line has always been disable_wifi's ifconfig down: the onboard
# driver stays loaded (sleep unloads it separately) and so does a dongle's -
# cheap to turn back on, and the watchdog unloads it when the dongle is pulled.
device_wifi_power_off() {
    return 0
}

device_ensure_wifi_interface() {
    [ -d /sys/class/net/wlan0 ] && return 0
    if usb_wifi_dongle_active; then
        _left=5
        while [ "$_left" -gt 0 ]; do
            [ -d /sys/class/net/wlan0 ] && return 0
            sleep 1
            _left=$((_left - 1))
        done
        log_message "USB WiFi: dongle active but wlan0 missing"
        return 1
    fi
    usb_wifi_onboard_restore
}

fi # WIFI_USB_MODULES_DIR
