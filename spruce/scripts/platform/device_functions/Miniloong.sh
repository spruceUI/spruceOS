#!/bin/sh
# Miniloong Pocket 1 device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit. Anything
# marked UNVERIFIED was measured on the vendor firmware, not under dArkMoss.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/dArkMossCommon.sh"

# The codec exposes the jack as its first control on the vendor kernel. UNVERIFIED.
are_headphones_plugged_in() {
    amixer cget numid=1 2>/dev/null | grep -q 'values=on'
}

  ##################
#####   RUMBLE   #####
  ##################

rumble_pwm_dir() {
    echo "/sys/class/pwm/${RUMBLE_PWMCHIP:-pwmchip0}/pwm${RUMBLE_PWM_CHANNEL:-0}"
}

# Export once, never unexport: unexporting latches the motor ON on this driver.
# Enable off before period, or every other write fails with EINVAL.
rumble_pwm_init() {
    _chip="/sys/class/pwm/${RUMBLE_PWMCHIP:-pwmchip0}"
    _pwm="$(rumble_pwm_dir)"
    [ -d "$_chip" ] || return 0
    [ -d "$_pwm" ] || echo "${RUMBLE_PWM_CHANNEL:-0}" > "$_chip/export" 2>/dev/null
    [ -d "$_pwm" ] || return 0
    echo 0 > "$_pwm/enable" 2>/dev/null
    echo "${RUMBLE_PWM_PERIOD:-1000000}" > "$_pwm/period" 2>/dev/null
    echo normal > "$_pwm/polarity" 2>/dev/null
    echo 0 > "$_pwm/duty_cycle" 2>/dev/null
}

# PWM when the channel exists, otherwise the common evdev rumble.
vibrate() {
    _pwm="$(rumble_pwm_dir)"
    if [ ! -d "$_pwm" ]; then
        darkmoss_vibrate "$@"
        return
    fi
    _duration=50
    _intensity=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --intensity) _intensity="$2"; shift ;;
            *[!0-9]*) ;;
            *) _duration="$1" ;;
        esac
        shift
    done
    [ -n "$_intensity" ] || _intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"
    [ "$_intensity" = "Off" ] && return 0
    _period="${RUMBLE_PWM_PERIOD:-1000000}"
    case "$_intensity" in
        Strong) _duty=$_period ;;
        Weak)   _duty=$((_period / 4)) ;;
        *)      _duty=$((_period / 2)) ;;
    esac
    echo "$_duty" > "$_pwm/duty_cycle" 2>/dev/null
    echo 1 > "$_pwm/enable" 2>/dev/null
    sleep "$(awk "BEGIN{print $_duration/1000}")"
    echo 0 > "$_pwm/enable" 2>/dev/null
    echo 0 > "$_pwm/duty_cycle" 2>/dev/null
}

  ####################
#####   BOOT   #####
  ####################

device_init() {
    resolve_pad_node
    log_message "$PLATFORM: TF2 is ${SD_DEV:-<unresolved>} at $SD_MOUNTPOINT"
    resolve_key_event_node
    setup_mainui_alias
    rumble_pwm_init
    darkmoss_wifi_up
    darkmoss_debug_dump
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e $EVENT_PATH_READ_INPUTS_SPRUCE"
}

# The rk817 is configured to power-cycle every rail on a SoC reset, so a plain
# reboot never comes back. SYS_CFG3 bits 7:6 set to "reset registers only"
# right before the reboot makes it return. Needs i2c-tools on the base.
device_prepare_for_reboot() {
    command -v i2cset >/dev/null 2>&1 || { log_message "Miniloong: i2cset missing, rk817 left as is"; return 0; }
    _cur="$(i2cget -f -y 0 0x20 0xf4 2>/dev/null)"
    case "$_cur" in 0x[0-9a-fA-F][0-9a-fA-F]) ;; *) _cur=0x18 ;; esac
    _new=$(( (_cur & 0x3f) | 0x40 ))
    i2cset -f -y 0 0x20 0xf4 "$_new" 2>/dev/null
    log_message "Miniloong: rk817 SYS_CFG3 $_cur -> $(printf '0x%02x' "$_new") before reboot"
}

# Indices from the sdl2 driver on the vendor firmware; UNVERIFIED for udev.
set_default_ra_hotkeys() {
    RA_FILE="/mnt/SDCARD/Saves/ra-configs/retroarch-$PLATFORM.cfg"
    log_message "Resetting RetroArch hotkeys to Spruce defaults."
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
