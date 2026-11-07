#!/bin/sh

# oakMOSS on the A133P: what depends on the chip and the base image built for it (our Tina on SD1), over the
# chip file the stock TrimUI A133P boards share (platform/a133p.sh). oakMOSSCommon.sh sources this first, for
# the boards whose cfg sets PLATFORM_CHIP="a133p"; the TrimUI userland is not on this base.

. "/mnt/SDCARD/spruce/scripts/platform/a133p.sh"

# The base's /usr/bin/timeout is BusyBox 1.27's, which wants -t SECS and fails on
# the "timeout SECS PROG" form spruce's scripts use (bluetooth.sh, asound-setup.sh).
timeout() {
    /mnt/SDCARD/spruce/bin64/busybox timeout "$@"
}

# The rumble motor, the only pin spruce drives on these boards: RUMBLE_GPIO from the cfg.
# On the Zero 40 and XU20 it is PH3 (gpio227), the enable pin of the stock trees'
# "io-vibrator" regulator, which our trees leave to userland - felt on both 2026-09-24.
# The Zero 28 has no motor, so its cfg says "none" and nothing is driven. Needs sysfs GPIO
# in the kernel (oakMOSS 020).
# This used to be the TrimUI Brick's init, which also drove PD11 high and exported PH19:
# neither is a MagicX pin, and PH19 is a pad button here.
init_gpio_a133p() {
    case "$RUMBLE_GPIO" in
        gpio[0-9]*) ;;
        *) return 0 ;;
    esac
    if [ ! -w /sys/class/gpio/export ]; then
        log_message "oakMOSS: no sysfs GPIO in this kernel, rumble unavailable" -v
        return 0
    fi
    [ -d "/sys/class/gpio/$RUMBLE_GPIO" ] || echo "${RUMBLE_GPIO#gpio}" > /sys/class/gpio/export
    printf '%s' out > "/sys/class/gpio/$RUMBLE_GPIO/direction"
    printf '%s' 0 > "/sys/class/gpio/$RUMBLE_GPIO/value"
}

# The Tina base ships OpenWrt's wpa_supplicant service (S96), which procd starts on
# wlan0 a second after ours and disconnects it. spruce owns the radio, so it goes.
oakmoss_disown_base_supplicant() {
    if [ -n "$(ls /etc/rc.d/[SK]??wpa_supplicant 2>/dev/null)" ]; then
        /etc/init.d/wpa_supplicant disable >/dev/null 2>&1
        log_message "oakMOSS: disabled the base image's wpa_supplicant service; spruce owns the radio"
    fi
    ubus call service delete '{"name":"wpa_supplicant"}' >/dev/null 2>&1
    pkill -f 'wpa_supplicant.*-O/etc/wifi/sockets' 2>/dev/null
    return 0
}

# Battery. The AXP2202 gauge read 0-1 % on a healthy cell (Zero 40), so a low
# reading with a good voltage becomes an estimate and holds the shutdown off.
# Never on the charger: charging lifts the terminal voltage, and a flat cell
# (gauge 1 %, truly empty) read 3704 mV and showed 40 % (Zero 28, 2026-09-27).
OAKMOSS_VBAT_EMPTY_MV=3400
OAKMOSS_VBAT_FULL_MV=4150
OAKMOSS_VBAT_TRUST_MV=3500

oakmoss_battery_mv() {
    uv=$(cat "$BATTERY/voltage_now" 2>/dev/null)
    case "$uv" in ''|*[!0-9]*) echo ""; return 1 ;; esac
    if [ "$uv" -gt 100000 ]; then echo $((uv / 1000)); else echo "$uv"; fi
}

device_get_battery_percent() {
    cap=$(cat "$BATTERY/capacity" 2>/dev/null)
    case "$cap" in ''|*[!0-9]*) echo "$cap"; return ;; esac
    if [ "$cap" -le 1 ] && [ "$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)" != "1" ]; then
        mv=$(oakmoss_battery_mv)
        if [ -n "$mv" ] && [ "$mv" -ge "$OAKMOSS_VBAT_TRUST_MV" ]; then
            est=$(( (mv - OAKMOSS_VBAT_EMPTY_MV) * 100 / (OAKMOSS_VBAT_FULL_MV - OAKMOSS_VBAT_EMPTY_MV) ))
            [ "$est" -gt 100 ] && est=100
            [ "$est" -lt 2 ] && est=2
            [ -e /tmp/oakmoss_gauge_warned ] || { log_message "oakMOSS battery: gauge says ${cap}% at ${mv} mV; using voltage estimate ${est}%"; touch /tmp/oakmoss_gauge_warned; }
            echo "$est"; return
        fi
    fi
    echo "$cap"
}

device_low_battery_shutdown_ok() {
    if [ "$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)" = "1" ]; then
        log_message "oakMOSS battery: charger online, not forcing a shutdown"
        return 1
    fi
    mv=$(oakmoss_battery_mv)
    if [ -n "$mv" ] && [ "$mv" -ge "$OAKMOSS_VBAT_TRUST_MV" ]; then
        log_message "oakMOSS battery: ${mv} mV, gauge not trusted, not forcing a shutdown"
        return 1
    fi
    return 0
}

# The TrimUI boards' real-sleep path (a133p.sh, overridden by the faux-sleep functions
# below), with one difference: only a module this path unloaded is loaded again, since the
# Zero 28's radio is an RTL8188ES, not the XR829 a133p.sh reloads unconditionally. The
# XR829 (Zero 40) has to go: loaded and associated, it refuses the suspend (-EBUSY).
OAKMOSS_SLEEP_UNLOADED=/tmp/oakmoss_sleep_unloaded
oakmoss_real_enter_sleep() {
    log_message "Entering sleep (suspend to RAM) w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    wifi_request suspend --wait
    usb_wifi_note_sleep
    usb_wifi_tear_down
    rm -f "$OAKMOSS_SLEEP_UNLOADED"
    if usb_wifi_module_loaded xradio_wlan && rmmod xradio_wlan; then
        echo xradio_wlan > "$OAKMOSS_SLEEP_UNLOADED"
    fi
    [ -n "$OAKMOSS_PM_ASYNC" ] && echo "$OAKMOSS_PM_ASYNC" > /sys/power/pm_async 2>/dev/null
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

oakmoss_real_exit_sleep() {
    clear_wake_alarm "$WAKE_ALARM_PATH"
    if usb_wifi_wait_after_resume; then
        wifi_request apply --wait
        return 0
    fi
    _mod=$(cat "$OAKMOSS_SLEEP_UNLOADED" 2>/dev/null)
    rm -f "$OAKMOSS_SLEEP_UNLOADED"
    if [ -n "$_mod" ]; then
        modprobe "$_mod"
        if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON" 2>/dev/null)" = 1 ]; then
            for _ in 1 2 3 4 5; do
                ip link show wlan0 >/dev/null 2>&1 && break
                sleep 1
            done
        fi
    fi
    wifi_request apply --wait
    log_message "Left sleep (suspend to RAM)"
}

OAKMOSS_SLEEP_STOP="MainUI retroarch ra64.trimui drastic drastic64 PPSSPPSDL_TrimUI PPSSPPSDL_$PLATFORM scummvm ffplay OpenBOR_mod OpenBOR_new mupen64plus"
OAKMOSS_SLEEP_BRIGHTNESS=/tmp/oakmoss_sleep_brightness

# The panel's raw brightness through /dev/disp (DISP_LCD_GET/SET_BRIGHTNESS). Raw on
# purpose: the level is mirrored on the boards whose backlight PWM is inverted, so sleep
# saves and restores the driver's value instead of re-deriving it from the user's level.
oakmoss_disp_brightness() {
    "$DEVICE_PYTHON3_PATH" - "$@" <<'EOF'
import ctypes, fcntl, os, sys
fd = os.open("/dev/disp", os.O_RDWR)
try:
    if sys.argv[1] == "get":
        print(fcntl.ioctl(fd, 0x103, (ctypes.c_ulong * 4)(0, 0, 0, 0)))
    else:
        fcntl.ioctl(fd, 0x102, (ctypes.c_ulong * 4)(0, int(sys.argv[2]), 0, 0))
finally:
    os.close(fd)
EOF
}

# The panel only, nothing saved: PyUI's backlightCmd (App/PyUI/set-backlight.sh) calls it
# for every change. PyUI keeps the level itself, and the screensaver's dim to level 1 must
# never be saved as the user's level.
apply_backlight() {
    oakmoss_disp_brightness set "$(oakmoss_backlight_raw "$1")" 2>/dev/null
}

# Only the Brick reads the TrimUI line's Fn switch on oakMOSS (BrickOakMOSS.sh). a133p.sh reads it from gpio243 (TrimUI's
# PH19); on MagicX that pin is L1, so the shared reader must not apply here - nothing, which
# apply-switch-action treats as "no switch". The XU20's extra button is its Home key (XU20.sh),
# never the switch or an Fn key (switchAction/fnF1Action/fnF2Action do not list MagicX).
device_get_switch_position() {
    :
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    if [ "$OAKMOSS_REAL_SLEEP" = "1" ]; then
        oakmoss_real_enter_sleep
        return
    fi
    log_message "Entering pseudo sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    # The power watchdog holds the power key with an exclusive grab and runs
    # sleep_helper in the foreground, so sleep_helper's own reader would never see the
    # wake press. Drop the grab; the watchdog restarts its reader when sleep_helper returns.
    kill $(pgrep -f "getevent.*-exclusive") 2>/dev/null
    killall -q -STOP $OAKMOSS_SLEEP_STOP 2>/dev/null
    oakmoss_disp_brightness get > "$OAKMOSS_SLEEP_BRIGHTNESS" 2>/dev/null
    # The darkest raw value: 1, or 255 where the PWM is inverted (OAKMOSS_BACKLIGHT_REVERSED).
    if [ "$OAKMOSS_BACKLIGHT_REVERSED" = "1" ]; then _dark=255; else _dark=1; fi
    oakmoss_disp_brightness set "$_dark" 2>/dev/null
    echo 4 > /sys/class/graphics/fb0/blank 2>/dev/null
}

device_exit_sleep() {
    if [ "$OAKMOSS_REAL_SLEEP" = "1" ]; then
        oakmoss_real_exit_sleep
        return
    fi
    echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
    _raw=$(cat "$OAKMOSS_SLEEP_BRIGHTNESS" 2>/dev/null)
    rm -f "$OAKMOSS_SLEEP_BRIGHTNESS"
    case "$_raw" in
        ''|*[!0-9]*) _raw=128 ;;
    esac
    oakmoss_disp_brightness set "$_raw" 2>/dev/null
    killall -q -CONT $OAKMOSS_SLEEP_STOP 2>/dev/null
    log_message "Left pseudo sleep (brightness raw $_raw)"
}

# Volume. There is no vendor volume daemon on this base (a133p.sh leaves set_volume
# to the vendor layer), so the codec is driven directly and the level lives in
# 'digital volume' (0..63).
OAKMOSS_DIGITAL_VOLUME_FLOOR=63
OAKMOSS_DIGITAL_VOLUME_QUIETEST=41

oakmoss_apply_volume() {
    vol="${1:-0}"
    case "$vol" in ''|*[!0-9]*) vol=0 ;; esac
    if [ "$vol" -le 0 ]; then
        att=$OAKMOSS_DIGITAL_VOLUME_FLOOR
    else
        [ "$vol" -gt 20 ] && vol=20
        att=$(( (OAKMOSS_DIGITAL_VOLUME_QUIETEST * (20 - vol) + 9) / 19 ))
    fi
    amixer sset 'digital volume' "$att" >/dev/null 2>&1
}

# The chip's own step in the base's device_init: the rumble GPIO (BrickCommon.sh brings the Brick's).
oakmoss_chip_init() {
    init_gpio_a133p
}
