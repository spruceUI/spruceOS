#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common32bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/miyoo-mini-system.json"
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
    log_message "Setting cpu to ondemand"
    echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    cpuclock 1300
}

set_performance() {
    log_message "Setting cpu to performance"
    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    cpuclock 1400
}

# PyUI's screensaver asks for this at the menu. Models opt in with MINI_POWERSAVE_MHZ in their
# overlay (cpufreq's own powersave is 400 MHz); the rest keep the smart clock, as before.
set_powersave() {
    if [ -n "${MINI_POWERSAVE_MHZ:-}" ]; then
        log_message "Setting cpu to powersave (${MINI_POWERSAVE_MHZ} MHz)"
        cpuclock "$MINI_POWERSAVE_MHZ"
    else
        set_smart
    fi
}

set_overclock() {
    overclock_speed="$(get_config_value '.menuOptions."System Settings".overclockSpeedMiyooMini.selected' "1600")"

    log_message "Setting cpu to performance"
    log_message "Setting overclock to ${overclock_speed}MHz"

    echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor    
    cpuclock "$overclock_speed"
}

# ra32.mini re-pins the clock in this file at start, after its own menu and on SIGCONT;
# without it, leaving RetroArch's menu drops the CPU to 1200 MHz until the game is closed.
RA_CPUCLOCK_FILE="/mnt/SDCARD/RetroArch/cpuclock.txt"
RA_CPUCLOCK_MARK="# written by spruce MiyooMini.sh"

mode_clock_mhz() {
    case "$1" in
        Performance) echo 1400 ;;
        Overclock) get_config_value '.menuOptions."System Settings".overclockSpeedMiyooMini.selected' "1600" ;;
        *) echo 1300 ;;
    esac
}

# Models opt in from device_functions/miyoomini/ once measured (the Mini Plus has); the rest
# drop the file spruce wrote, so a card moved from a Plus does not pin another model's clock.
pin_ra_cpuclock() {
    if grep -qF "$RA_CPUCLOCK_MARK" "$RA_CPUCLOCK_FILE" 2>/dev/null; then
        rm -f "$RA_CPUCLOCK_FILE"
    fi
}

# Per-model boot quirks; device_functions/miyoomini/$MINI_MODEL.sh overrides it
mini_model_init() {
    :
}

device_init() {
    # Enable GPIO48 for vibration motor
    echo 48 > /sys/class/gpio/export

    mini_model_init

    # Export and prime the pwm backlight channel.
    #
    # This used to sit inside the Plus branch above, which left the OG Mini and
    # the V4 with no pwm0 node at all -- /sys/class/pwm/pwmchip0 exists but is
    # never exported. Nothing could drive the backlight, and device_exit_sleep,
    # which restores brightness through that same node, had nothing to write to
    # either. The model overlay sets MINI_PRIME_PWM_BACKLIGHT; the Mini Flip leaves
    # it unset: its backlight already works and it does not come through here today.
    if [ "${MINI_PRIME_PWM_BACKLIGHT:-}" = "true" ]; then
        # export brightness settings
        [ -d /sys/class/pwm/pwmchip0/pwm0 ] || echo 0 > /sys/class/pwm/pwmchip0/export
        # Unsure what this value should be, 1k seems to work
        echo 1000 >  /sys/class/pwm/pwmchip0/pwm0/period
        backlight=$(jq -r '.backlight' "$SYSTEM_JSON")
        duty_cycle=$((backlight * 10))
        echo "$duty_cycle" > /sys/class/pwm/pwmchip0/pwm0/duty_cycle
        echo 1 >  /sys/class/pwm/pwmchip0/pwm0/enable
    fi
    killall -9 main ### SUPER important in preventing .tmp_update suicide

    # The stock firmware starts an unauthenticated root shell on telnet; Onion kills it the same way.
    pkill -9 -f "telnetd -l sh" 2>/dev/null
}

# Sleeps floor at 10ms, so tiers are pulse rate, not strength.
vibrate() {
    duration=400
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

    [ "$intensity" = "Off" ] && return 0

    _g=/sys/class/gpio/gpio48
    echo out > $_g/direction

    # 0 drives the motor, 1 stops it
    case "$intensity" in
        "Weak")   _on=0.003; _off=0.009; _cycles=$((duration / 31)) ;;
        "Medium") _on=0.005; _off=0.005; _cycles=$((duration / 20)) ;;
        *)        _cycles=0 ;;
    esac

    if [ "$_cycles" -lt 1 ]; then
        echo 0 > $_g/value
        sleep "$(awk "BEGIN{print $duration/1000}")"
        echo 1 > $_g/value
        return 0
    fi

    _i=0
    while [ "$_i" -lt "$_cycles" ]; do
        echo 0 > $_g/value; sleep $_on
        echo 1 > $_g/value; sleep $_off
        _i=$((_i + 1))
    done
    echo 1 > $_g/value
}

display_kill() {
    log_message "Only PyUI is supported on Miyoo Mini for display functionality" -v
}

display() {
    log_message "Only PyUI is supported on Miyoo Mini for display functionality" -v
}

rgb_led() {
    log_message "rgb led not supported on miyoo mini" -v
}

enable_or_disable_rgb() {
    log_message "rgb led not supported on miyoo mini" -v
}

enter_sleep() {
    log_message "Keymon handles sleep, not spruce" -v
}

get_current_volume() {
    log_message "Intentionally do not let spruce modify volume" -v
}

new_execution_loop() {
    pidof audioserver >/dev/null || audioserver &
}

setup_for_retroarch(){
    export CORE_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"

    # Without audioserver, RA's oss driver drops all audio during fast-forward.
    # The boot-time start fails on some units, and DraStic/PICO-8 kill it.
    if ! pidof audioserver >/dev/null; then
        LD_PRELOAD= audioserver >/dev/null 2>&1 &
        sleep 0.5
    fi

    pin_ra_cpuclock

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
    has_v4_screen && fbset -g 752 560 752 560 32
}

post_pyui_exit(){
    log_message "MiyooMini doesn't need to do anything after pyui exit (should we call freemma?)" -v
}

# MINI_HAS_LID comes from the model overlay (the Mini Flip's hall sensor)
launch_startup_watchdogs(){
    launch_common_startup_watchdogs_v2 "${MINI_HAS_LID:-false}"
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
    log_message "TODO: set_default_ra_hotkeys" -v
}

volume_down() {
    VOLUME_LV=$(get_volume_level)
    if [ $VOLUME_LV -gt 0 ] ; then
        VOLUME_LV=$((VOLUME_LV-1))
        set_volume "$(( VOLUME_LV ))"
    fi
}

volume_up() {
    VOLUME_LV=$(get_volume_level)
    if [ $VOLUME_LV -lt 20 ] ; then
        VOLUME_LV=$((VOLUME_LV+1))
        set_volume "$(( VOLUME_LV ))"
    fi
}

get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON"
}

set_volume() {
    # NOTE: This won't always work. They will often just error.
    # But sometimes they do work. It's based on if something else is already controlling the volume.
    # The main purpose of this is for NDS volume since drastic does some weird stuff
    # Can add more apps as needed
    if pgrep -f "./drastic(32|64)?" >/dev/null; then
        VOLUME_LV="$1"
        SAVE_TO_CONFIG="${2:-true}"   # Optional 2nd arg, defaults to true
        /mnt/SDCARD/spruce/miyoomini/bin/mm_set_volume.py "$VOLUME_LV" &

        # Call save_volume_to_config_file only if SAVE_TO_CONFIG is true
        if [ "$SAVE_TO_CONFIG" = true ]; then
            save_volume_to_config_file "$VOLUME_LV"
        fi
    fi
}


current_backlight() {
    jq -r '.backlight' "$SYSTEM_JSON"
}

set_backlight() {
    local value="$1"

    # Clamp between 0–10
    [ "$value" -lt 0 ] && value=0
    [ "$value" -gt 10 ] && value=10

    jq ".backlight = $value" "$SYSTEM_JSON" > "$SYSTEM_JSON.tmp" && mv "$SYSTEM_JSON.tmp" "$SYSTEM_JSON"
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

set_event_arg_for_idlemon() {
    EVENT_ARG="-e /dev/input/event0"
}

device_get_charging_status() {
    if is_mini_og; then
        charging="$(cat /sys/devices/gpiochip0/gpio/gpio59/value)"
    else
        charging="$(/customer/app/axp_test 2>/dev/null | jq -r '.charging // 0' )"
    fi
    if [ "$charging" -eq 0 ]; then
        echo "Discharging"
    else
        echo "Charging"
    fi
}

device_get_battery_percent() {
    if is_mini_og; then
        /mnt/SDCARD/spruce/miyoomini/bin/read_battery || echo 0
    else
        /customer/app/axp_test 2>/dev/null | jq -r '.battery // empty'
    fi
}

# RetroArch runs as ra32.mini (RA_BIN in MiyooMini.cfg); retroarch stays for anything started by that name.
EMU_LIST="retroarch ra32.mini scummvm pico8_dyn drastic OpenBOR OpenBOR_mod OpenBOR_new ffplay MainUI"
BRIGHTNESS_FILE="/sys/devices/soc0/soc/1f003400.pwm/pwm/pwmchip0/pwm0/duty_cycle"
SCREEN_BLANK_FILE="/proc/mi_modules/fb/mi_fb0"
BUTTON_ENABLE_FILE="/sys/module/gpio_keys_polled/parameters/button_enable"
LID_HALL_FILE="/sys/devices/soc0/soc/soc:hall-mh248/hallvalue"

device_enter_sleep() {
    killall -9 keymon
    killall -q -SIGSTOP $(echo $EMU_LIST) 2>/dev/null
    cat "$BRIGHTNESS_FILE" > /tmp/saved_brightness 2>/dev/null  # backup current brightness
    echo "GUI_SHOW 0 off" > "$SCREEN_BLANK_FILE" 2>/dev/null    # blank the screen
    echo "0" > "$BRIGHTNESS_FILE" 2>/dev/null                   # set brightness to 0
    touch /tmp/screen_blanked                                   # create flag file
    cpuclock 100                                                # slow cpu to a crawl
}

device_exit_sleep() {
    cpuclock 1600                                               # wake up cpu speed
    /customer/app/keymon &
    killall -q -SIGCONT $(echo $EMU_LIST) 2>/dev/null
    echo "GUI_SHOW 0 on" > "$SCREEN_BLANK_FILE" 2>/dev/null     # unblank screen
    if [ -f /tmp/saved_brightness ]; then
        cat /tmp/saved_brightness > "$BRIGHTNESS_FILE" 2>/dev/null  # restore previous brightness
    else
        echo "50" > "$BRIGHTNESS_FILE" 2>/dev/null              # default if previous not found
    fi
    rm -f /tmp/screen_blanked /tmp/saved_brightness             # clean up temp files

    sleep 0.5
    send_event /dev/input/event0 116:1 


    mini_reenable_buttons

    if pidof retroarch ra32.mini >/dev/null; then
        # Back to the game's own CPU mode where it was pinned at launch, else smart mode
        if grep -qF "$RA_CPUCLOCK_MARK" "$RA_CPUCLOCK_FILE" 2>/dev/null; then
            cpuclock "$(head -n 1 "$RA_CPUCLOCK_FILE")"
        else
            set_smart
        fi
    fi
}

# Input back on after sleep; the Mini Flip's model file overrides it.
# TODO (no OG Mini to test on): this may only be needed on the Plus.
mini_reenable_buttons() {
    echo 1 > /sys/module/gpio_keys_polled/parameters/button_enable
}

# The Mini kernels (4.9.84 #968, #1136, #1313) have no zram module: skip enable_zram.sh and its log line
device_supports_zram() {
    return 1
}

device_lid_sensor_ready() {
    [ -e "$LID_HALL_FILE" ]
}

device_lid_open(){
    if [ -e "$LID_HALL_FILE" ]; then
        # Builtins only: the lid watchdog asks twice a second
        read -r _lid < "$LID_HALL_FILE" 2>/dev/null
        echo "${_lid%"${_lid#?}"}"
    else
        echo "1"
    fi
}

device_wifi_is_available() {
    case "$(get_miyoo_mini_variant)" in
        "MIYOO_MINI"|"MIYOO_MINI_V4")
            return 1 # False
            ;;
        *)
            return 0 # True
            ;;
    esac
}

device_prepare_for_ports_run() {
    log_message "device_prepare_for_ports_run uneeded on this device" -v
}

device_cleanup_after_ports_run() {
    log_message "device_cleanup_after_ports_run uneeded on this device" -v
}

device_uses_pseudo_sleep() {
    echo "true"
}

# Miyoo Mini subtype: helperFunctions resolves MINI_MODEL once at platform detection

# The OG Mini and the V4: no axp_test PMIC, no radio
is_mini_og() {
    case "${MINI_MODEL:-}" in
        MIYOO_MINI|MIYOO_MINI_V4) return 0 ;;
        *) return 1 ;;
    esac
}

# The OG Mini and V4 have no radio; without this a wifi=1 setting sends them through enable_wifi
device_has_wifi_radio() {
    ! is_mini_og
}

# The RTL8188FU driver loads from the card and axp_test powers the radio. Only
# when wlan0 is missing: re-powering a live radio would drop the connection.
device_wifi_power_on() {
    is_mini_og && return 1
    [ -d /sys/class/net/wlan0 ] && return 0
    # Log level 3 keeps the driver's warnings and errors; its default (4, info) fills dmesg with "Turbo EDCA" lines
    grep -q "^8188fu " /proc/modules 2>/dev/null || insmod /mnt/SDCARD/spruce/miyoomini/drivers/8188fu.ko rtw_drv_log_level=3 2>/dev/null
    ifconfig lo up 2>/dev/null
    /customer/app/axp_test wifion >/dev/null 2>&1
    _left=10
    while [ ! -d /sys/class/net/wlan0 ] && [ "$_left" -gt 0 ]; do
        sleep 1
        _left=$((_left - 1))
    done
}

# disable_wifi's ifconfig down is all that has ever turned it off
device_wifi_power_off() {
    return 0
}

# Nothing ever watched the Mini's link, and a restart here re-powers the chip
device_wifi_watchdog_enabled() {
    return 1
}

# The Mini's udhcpc needs its own script to set the address
device_start_dhcp_client() {
    pgrep -f "udhcpc.*wlan0" >/dev/null || udhcpc -i wlan0 -s /etc/init.d/udhcpc.script -b -t 5 -T 3
}

# The V4 and Mini Flip panel, as the model overlay states it
has_v4_screen() {
    [ "${DISPLAY_WIDTH:-}" = "752" ]
}

get_miyoo_mini_variant() {
    echo "${MINI_MODEL:-}"
}

run_poweroff_cmd() {
    if is_mini_og; then
        reboot # OG Mini hangs if you use the poweroff command
    else
        poweroff
    fi
}

device_system_handles_sdcard_unmount() {
    # return 0 = true
    # return non-zero = false
    return 1
}

work_led_off() {
    echo 0 >${LED_PATH}/brightness
}

work_led_on() {
    echo 1 >${LED_PATH}/brightness
}

# What only one model does, last so its definitions win (as RGB20SX.sh over RGB30.sh)
if [ -f "/mnt/SDCARD/spruce/scripts/platform/device_functions/miyoomini/${MINI_MODEL:-}.sh" ]; then
    . "/mnt/SDCARD/spruce/scripts/platform/device_functions/miyoomini/$MINI_MODEL.sh"
fi
