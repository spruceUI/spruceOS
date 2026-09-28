#!/bin/sh

# MagicX A133P family: Mini Zero 28, Zero 40 and XU20 V32. The SoC-level functions
# come from a133p.sh, shared with the TrimUI A133P boards; the base OS is our own
# Tina on SD1, so nothing of TrimUI's userland is sourced here.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/a133p.sh"

# zero28 | zero40 | xu20, from the base image's marker. Images without one
# predate the marker and are Zero 28 (Moss-zero28 itself).
magicx_model() {
    m=$(tr -d '\r\n' < /usr/magicx/device 2>/dev/null)
    echo "${m:-zero28}"
}

# First /dev/input/eventN whose kernel name matches one of the patterns.
magicx_find_event_by_name() {
    for d in /sys/class/input/event*; do
        n=$(tr -d '\n' < "$d/device/name" 2>/dev/null) || continue
        for pat in "$@"; do
            # shellcheck disable=SC2254  # the pattern is meant to glob
            case "$n" in $pat) echo "/dev/input/$(basename "$d")"; return 0 ;; esac
        done
    done
    return 1
}

# The touchscreen node. The base image's tslib hint is authoritative when it exists;
# otherwise the first node advertising ABS_MT_POSITION_X, then a name match.
magicx_touch_event_path() {
    p=$(sed -n 's/^\(export \)\{0,1\}TSLIB_TSDEVICE=//p' /etc/tslib-env.sh 2>/dev/null | head -1 | tr -d '"')
    [ -n "$p" ] && [ -e "$p" ] && { echo "$p"; return 0; }
    for d in /sys/class/input/event*; do
        abs=$(cat "$d/device/capabilities/abs" 2>/dev/null) || continue
        low=${abs##* }
        [ -n "$low" ] || continue
        if [ $(( 0x$low >> 53 & 1 )) -eq 1 ]; then
            echo "/dev/input/$(basename "$d")"
            return 0
        fi
    done
    magicx_find_event_by_name "*[Tt]ouch*" "*ts*" "*gt9*" "*ft5*" "*goodix*" "*[Ff]ocal*" "*hyn*" "*cst*"
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
        log_message "MagicX: no sysfs GPIO in this kernel, rumble unavailable" -v
        return 0
    fi
    [ -d "/sys/class/gpio/$RUMBLE_GPIO" ] || echo "${RUMBLE_GPIO#gpio}" > /sys/class/gpio/export
    printf '%s' out > "/sys/class/gpio/$RUMBLE_GPIO/direction"
    printf '%s' 0 > "/sys/class/gpio/$RUMBLE_GPIO/value"
}

# trimui's runtime_mounts_a133p also runs spruce/brick/sdl2/bind.sh, which binds
# TrimUI's stock SDL2 into the card; PyUI on MagicX loads /usr/magicx/lib directly.
runtime_mounts_magicx() {
    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    wait
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/flip/bin/MainUI
}

# Resolve the input nodes at boot instead of trusting the cfg's numbering: they
# enumerate in whatever order the drivers probe. The cfg values stay as fallbacks.
magicx_resolve_event_paths() {
    # The simplepad driver (UART MCU pad) registers its input device as
    # "magicx-input" (strings in simplepad.ko), not under the generic names.
    pad=$(magicx_find_event_by_name "*magicx-input*" "*magicx*" "*simplepad*" "*[Gg]amepad*" "*[Jj]oystick*" "*joypad*")
    if [ -n "$pad" ]; then
        export EVENT_PATH_SEND_TO_DRASTIC="$pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$pad"
        export EVENT_PATH_READ_INPUTS_SPRUCE="$pad"
        export EVENT_PATH_VOLUME="$pad"
    fi
    pwr=$(magicx_find_event_by_name "*axp*pek*" "*[Pp]ower*" "*pwr*")
    [ -n "$pwr" ] && export EVENT_PATH_POWER="$pwr"
    if [ "$DEVICE_HAS_TOUCHSCREEN" = "true" ]; then
        t=$(magicx_touch_event_path) && export EVENT_PATH_TOUCH="$t"
    fi
    log_message "MagicX input nodes: pad=${EVENT_PATH_READ_INPUTS_SPRUCE} power=${EVENT_PATH_POWER} touch=${EVENT_PATH_TOUCH:-none}"
}

# The Tina base ships OpenWrt's wpa_supplicant service (S96), which procd starts on
# wlan0 a second after ours and disconnects it. spruce owns the radio, so it goes.
magicx_disown_base_supplicant() {
    if [ -n "$(ls /etc/rc.d/[SK]??wpa_supplicant 2>/dev/null)" ]; then
        /etc/init.d/wpa_supplicant disable >/dev/null 2>&1
        log_message "MagicX: disabled the base image's wpa_supplicant service; spruce owns the radio"
    fi
    ubus call service delete '{"name":"wpa_supplicant"}' >/dev/null 2>&1
    pkill -f 'wpa_supplicant.*-O/etc/wifi/sockets' 2>/dev/null
    return 0
}

# The onboard radio differs per board and neither driver may autoload: Zero 28
# 8189es, Zero 40 XR829. Each cfg names its module; kmsg is streamed to the card.
MAGICX_RADIO_KMSG=/mnt/SDCARD/Saves/spruce/radio-kmsg.log

magicx_load_onboard_radio() {
    [ -n "$WIFI_ONBOARD_MODULE" ] || return 0
    if usb_wifi_module_loaded "$WIFI_ONBOARD_MODULE"; then
        return 0
    fi
    # Every driver any board in this family ships, dependents before their base: one of
    # these probing the SDIO bus first is what knocked the real radio off it.
    for _other in 8189es xradio_wlan xradio_core xradio_mac xr829 xradio_btlpm \
                  aic8800_fdrv aic8800_btlpm aic8800_bsp sprdwl_ng sprdbt_tty uwe5622_bsp_sdio; do
        [ "$_other" = "$WIFI_ONBOARD_MODULE" ] && continue
        usb_wifi_module_loaded "$_other" && rmmod "$_other" 2>/dev/null
    done
    mkdir -p "$(dirname "$MAGICX_RADIO_KMSG")" 2>/dev/null
    cat /dev/kmsg > "$MAGICX_RADIO_KMSG" 2>/dev/null &
    _kmsg_pid=$!
    if [ -n "$MAGICX_RADIO_MODULES_DIR" ] && [ -f "$MAGICX_RADIO_MODULES_DIR/$WIFI_ONBOARD_MODULE.ko" ]; then
        # Card-carried modules, for a board not running the kernel ours were built against.
        # No board in the family needs this now; the order below is the XR829 stack's.
        rc=0
        for _m in xradio_mac xradio_core "$WIFI_ONBOARD_MODULE"; do
            [ -f "$MAGICX_RADIO_MODULES_DIR/$_m.ko" ] || continue
            usb_wifi_module_loaded "$_m" && continue
            insmod "$MAGICX_RADIO_MODULES_DIR/$_m.ko" 2>/tmp/magicx_radio_err || { rc=$?; break; }
        done
        _src="card:$MAGICX_RADIO_MODULES_DIR"
    else
        modprobe "$WIFI_ONBOARD_MODULE" 2>/tmp/magicx_radio_err; rc=$?
        _src="modprobe"
    fi
    for _ in 1 2 3 4 5; do
        [ -d /sys/class/net/wlan0 ] && break
        sleep 1
    done
    kill "$_kmsg_pid" 2>/dev/null
    sync
    log_message "MagicX radio: $_src $WIFI_ONBOARD_MODULE rc=$rc $(head -1 /tmp/magicx_radio_err 2>/dev/null); wlan0=$([ -d /sys/class/net/wlan0 ] && echo yes || echo no); sdio=$(ls /sys/bus/sdio/devices 2>/dev/null | tr '\n' ' '); $(grep -a -i 'xradio\|sbus\|RTW: \|8189\|firmware\|sdd\|Unable to handle\|BUG' "$MAGICX_RADIO_KMSG" 2>/dev/null | head -8 | cut -c1-160 | tr '\n' '|')"
    return 0
}

# Touch. The touch drivers ship in the base as modules nothing autoloads (oakMOSS
# sdk-patches/tree/090: XU20 hynitron, Zero 40 axs15205): built in, the XU20's probe
# ran on the kernel's init thread and stalled 6 of 8 boots before init (initcall
# marker, 2026-09-18). The cfg names the module (MAGICX_TOUCH_MODULE). Like the
# onboard radio it is loaded here, once the board has settled - in the background,
# with a bounded wait for its input node, so a probe that hangs costs touch for this
# session instead of the boot. The kernel log around the load goes to the card.
MAGICX_TOUCH_KMSG=/mnt/SDCARD/Saves/spruce/touch-kmsg.log

magicx_load_touch() {
    [ -n "$MAGICX_TOUCH_MODULE" ] || return 0
    usb_wifi_module_loaded "$MAGICX_TOUCH_MODULE" && return 0
    mkdir -p "$(dirname "$MAGICX_TOUCH_KMSG")" 2>/dev/null
    cat /dev/kmsg > "$MAGICX_TOUCH_KMSG" 2>/dev/null &
    _kmsg_pid=$!
    _kmsg_from=$(dmesg 2>/dev/null | wc -l)
    modprobe "$MAGICX_TOUCH_MODULE" 2>/tmp/magicx_touch_err &
    _mp_pid=$!
    _node=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        _node=$(magicx_find_event_by_name "*hyn*" "*cst*" "*axs*") && break
        sleep 0.5
    done
    if kill -0 "$_mp_pid" 2>/dev/null; then
        _st="modprobe still running after 5 s"
    else
        wait "$_mp_pid"
        _st="rc=$?"
    fi
    kill "$_kmsg_pid" 2>/dev/null
    sync
    log_message "MagicX touch: $MAGICX_TOUCH_MODULE $_st; node=${_node:-none}; $(head -1 /tmp/magicx_touch_err 2>/dev/null) $(dmesg 2>/dev/null | tail -n +$((_kmsg_from + 1)) | grep -a -e hyn -e axs -e 'xfer timeout' -e 'Unable to handle' -e 'BUG:' | head -6 | cut -c1-160 | tr '\n' '|')"
    return 0
}

device_init() {
    runtime_mounts_magicx
    magicx_disown_base_supplicant
    magicx_seed_system_json

    export LD_LIBRARY_PATH="/usr/magicx/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib"

    init_gpio_a133p
    magicx_load_touch
    magicx_resolve_event_paths
    magicx_load_onboard_radio

    (
        syslogd -S
        hwclock -s -u
    ) &
    # Bluetooth: the base ships bluez and the XR829 BT firmware, but the HCI attach
    # sequence is not wired on this family yet; PyUI's Bluetooth toggle owns it.
    magicx_init_audio
    stage_ra_autoconfig

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash 2>/dev/null
        chmod +x /bin/bash 2>/dev/null
    fi
}

# RetroArch has no profile for this pad, so it announces "magicx-input
# (46098/26214) not configured, using fallback" at every launch.
#
# All three boards report the same name and ids (simplepad), but the XU20 has no
# sticks, the Zero 40 one and the Zero 28 two, so stage the variant that matches.
# Only sdl2: these boards run the 64-bit build. The binds are the ones the platform
# cfg already sets, so nothing changes but the notification. A card moves between
# boards, hence every boot. Same scheme as the Anbernic XX line.
stage_ra_autoconfig() {
    case "$PLATFORM" in
        XU20)   _ra_ac_variant="nosticks" ;;
        Zero40) _ra_ac_variant="onestick" ;;
        *)      _ra_ac_variant="twosticks" ;;
    esac
    _ra_ac_src="/mnt/SDCARD/RetroArch/platform/autoconfig/sdl2/magicx-input-${_ra_ac_variant}.cfg"
    _ra_ac_dst="/mnt/SDCARD/RetroArch/.retroarch/autoconfig/sdl2/magicx-input.cfg"
    if [ -f "$_ra_ac_src" ] && ! cmp -s "$_ra_ac_src" "$_ra_ac_dst"; then
        mkdir -p "${_ra_ac_dst%/*}"
        cp "$_ra_ac_src" "$_ra_ac_dst" && \
            log_message "Staged sdl2 pad profile ($_ra_ac_variant) for RetroArch"
    fi
    unset _ra_ac_variant _ra_ac_src _ra_ac_dst
}

# Battery. The AXP2202 gauge read 0-1 % on a healthy cell (Zero 40), so a low
# reading with a good voltage becomes an estimate and holds the shutdown off.
# Never on the charger: charging lifts the terminal voltage, and a flat cell
# (gauge 1 %, truly empty) read 3704 mV and showed 40 % (Zero 28, 2026-09-27).
MAGICX_VBAT_EMPTY_MV=3400
MAGICX_VBAT_FULL_MV=4150
MAGICX_VBAT_TRUST_MV=3500

magicx_battery_mv() {
    uv=$(cat "$BATTERY/voltage_now" 2>/dev/null)
    case "$uv" in ''|*[!0-9]*) echo ""; return 1 ;; esac
    if [ "$uv" -gt 100000 ]; then echo $((uv / 1000)); else echo "$uv"; fi
}

device_get_battery_percent() {
    cap=$(cat "$BATTERY/capacity" 2>/dev/null)
    case "$cap" in ''|*[!0-9]*) echo "$cap"; return ;; esac
    if [ "$cap" -le 1 ] && [ "$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)" != "1" ]; then
        mv=$(magicx_battery_mv)
        if [ -n "$mv" ] && [ "$mv" -ge "$MAGICX_VBAT_TRUST_MV" ]; then
            est=$(( (mv - MAGICX_VBAT_EMPTY_MV) * 100 / (MAGICX_VBAT_FULL_MV - MAGICX_VBAT_EMPTY_MV) ))
            [ "$est" -gt 100 ] && est=100
            [ "$est" -lt 2 ] && est=2
            [ -e /tmp/magicx_gauge_warned ] || { log_message "MagicX battery: gauge says ${cap}% at ${mv} mV; using voltage estimate ${est}%"; touch /tmp/magicx_gauge_warned; }
            echo "$est"; return
        fi
    fi
    echo "$cap"
}

device_low_battery_shutdown_ok() {
    if [ "$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)" = "1" ]; then
        log_message "MagicX battery: charger online, not forcing a shutdown"
        return 1
    fi
    mv=$(magicx_battery_mv)
    if [ -n "$mv" ] && [ "$mv" -ge "$MAGICX_VBAT_TRUST_MV" ]; then
        log_message "MagicX battery: ${mv} mV, gauge not trusted, not forcing a shutdown"
        return 1
    fi
    return 0
}

# Sleep is faux sleep, MinUI/Moss's model (none of their boards uses kernel suspend):
# suspend-to-RAM never came back on the MagicX stock boot chain (XU20 2026-09-18: after
# `echo mem` neither the power key nor the +300 s RTC alarm woke it, and no driver's
# resume ran). The panel goes dark and the session stops until sleep_helper's pseudo loop
# sees the power button, or its idle timer powers the board off. The radio stays up.
#
# Real suspend-to-RAM where the board has been proven to resume (MAGICX_REAL_SLEEP=1 in its
# cfg): the Zero 28 on the SDK's firmware and the Zero 40 on MagicX's both came back from
# `mem` on the RTC alarm (2026-09-24). The XU20 too, with its devices suspending one at a
# time (MAGICX_PM_ASYNC=0 in its cfg): async suspend never finished there (2026-09-28).
device_uses_pseudo_sleep() {
    if [ "$MAGICX_REAL_SLEEP" = "1" ]; then echo "false"; else echo "true"; fi
}

# The TrimUI boards' real-sleep path (a133p.sh, overridden by the faux-sleep functions
# below), with one difference: only a module this path unloaded is loaded again, since the
# Zero 28's radio is an RTL8188ES, not the XR829 a133p.sh reloads unconditionally. The
# XR829 (Zero 40) has to go: loaded and associated, it refuses the suspend (-EBUSY).
MAGICX_SLEEP_UNLOADED=/tmp/magicx_sleep_unloaded
magicx_real_enter_sleep() {
    log_message "Entering sleep (suspend to RAM) w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    wifi_request suspend --wait
    usb_wifi_note_sleep
    usb_wifi_tear_down
    rm -f "$MAGICX_SLEEP_UNLOADED"
    if usb_wifi_module_loaded xradio_wlan && rmmod xradio_wlan; then
        echo xradio_wlan > "$MAGICX_SLEEP_UNLOADED"
    fi
    [ -n "$MAGICX_PM_ASYNC" ] && echo "$MAGICX_PM_ASYNC" > /sys/power/pm_async 2>/dev/null
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

magicx_real_exit_sleep() {
    clear_wake_alarm "$WAKE_ALARM_PATH"
    if usb_wifi_wait_after_resume; then
        wifi_request apply --wait
        return 0
    fi
    _mod=$(cat "$MAGICX_SLEEP_UNLOADED" 2>/dev/null)
    rm -f "$MAGICX_SLEEP_UNLOADED"
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

# No MagicX board has a lid; sleep_helper's pseudo loop takes the power button only
# while this reads "1".
device_lid_open() {
    echo "1"
}

MAGICX_SLEEP_STOP="MainUI retroarch ra64.trimui drastic drastic64 PPSSPPSDL_TrimUI PPSSPPSDL_$PLATFORM scummvm ffplay OpenBOR_mod OpenBOR_new mupen64plus"
MAGICX_SLEEP_BRIGHTNESS=/tmp/magicx_sleep_brightness

# PyUI's SDL2 directory. The base's SDL2_image (2.0.3) predates QOI, so box art converted
# by "Optimize boxart" would not load. PySDL2 takes a single directory: link the base's
# SDL2 libraries (DEVICE_PYSDL2_DLL_PATH) next to PyUI's QOI-capable SDL2_image in tmpfs,
# as the Brick pairs them in spruce/brick/sdl2. Prints the directory.
magicx_pyui_sdl_dir() {
    _dir=/tmp/pyui-sdl2
    mkdir -p "$_dir"
    rm -f "${_dir:?}"/*
    for _lib in "${DEVICE_PYSDL2_DLL_PATH:-/usr/magicx/lib}"/libSDL2*; do
        case "$_lib" in
            */libSDL2_image*) ;;
            *) ln -s "$_lib" "$_dir/" ;;
        esac
    done
    ln -s /mnt/SDCARD/App/PyUI/dll/libSDL2_image-2.0.so "$_dir/"
    echo "$_dir"
}

# The panel's raw brightness through /dev/disp (DISP_LCD_GET/SET_BRIGHTNESS). Raw on
# purpose: the level is mirrored on the boards whose backlight PWM is inverted, so sleep
# saves and restores the driver's value instead of re-deriving it from the user's level.
magicx_disp_brightness() {
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

# Level 1..10 -> raw panel value, MagicX only. The curve is PyUI's own (DeviceCommon.
# map_backlight_from_10_to_full_255: 25 a step, 255 at 10), the one all three panels were
# tested on; a133p.sh's (level-1)*254/9+1 stays with the TrimUI boards. Mirrored where the
# backlight PWM is inverted (MAGICX_BACKLIGHT_REVERSED: the XU20 and the Zero 40).
magicx_backlight_raw() {
    val="$1"
    case "$val" in ''|*[!0-9]*) val=1 ;; esac
    [ "$val" -lt 1 ] && val=1
    [ "$val" -gt 10 ] && val=10
    if [ "$val" -eq 10 ]; then raw=255; else raw=$((val * 25)); fi
    [ "$MAGICX_BACKLIGHT_REVERSED" = "1" ] && raw=$((256 - raw))
    echo "$raw"
}

# The panel only, nothing saved: what PyUI calls for every change. PyUI keeps the level
# itself, and the screensaver's dim to level 1 must never be saved as the user's level.
magicx_apply_backlight() {
    magicx_disp_brightness set "$(magicx_backlight_raw "$1")" 2>/dev/null
}

# The brightness keys (buttons_watchdog -> brightness_up/down): the panel, then the level
# saved. Overrides a133p.sh's set_backlight (sourced above).
set_backlight() {
    val="$1"
    case "$val" in ''|*[!0-9]*) return 1 ;; esac
    [ "$val" -lt 1 ] && val=1
    [ "$val" -gt 10 ] && val=10
    magicx_apply_backlight "$val"
    tmp="${SYSTEM_JSON}.tmp.$$"
    jq ".backlight = $val" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON" || rm -f "$tmp"
}

# No MagicX board has the TrimUI line's Fn switch. a133p.sh reads it from gpio243 (TrimUI's
# PH19); on MagicX that pin is L1, so the shared reader must not apply here - nothing, which
# apply-switch-action treats as "no switch". The XU20's extra button is its Home key (below),
# never the switch or an Fn key (switchAction/fnF1Action/fnF2Action do not list MagicX).
device_get_switch_position() {
    :
}

# The XU20's extra face button, on images that give it KEY_HOMEPAGE (B_HOME in XU20.cfg):
# the same Home action as the Smart Pro S's top button (buttons_watchdog.sh calls this).
device_home_button_pressed() {
    action="$(get_config_value '.menuOptions."Button Settings".homeAction.selected' "Game Switcher")"
    perform_action "$action"
    case "$action" in
        "Game Switcher"|"Exit game")
            rm -f /tmp/cmd_to_run.sh
            rm -f /mnt/SDCARD/spruce/flags/lastgame.lock
            ;;
    esac
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    if [ "$MAGICX_REAL_SLEEP" = "1" ]; then
        magicx_real_enter_sleep
        return
    fi
    log_message "Entering pseudo sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    # The power watchdog holds the power key with an exclusive grab and runs
    # sleep_helper in the foreground, so sleep_helper's own reader would never see the
    # wake press. Drop the grab; the watchdog restarts its reader when sleep_helper returns.
    kill $(pgrep -f "getevent.*-exclusive") 2>/dev/null
    killall -q -STOP $MAGICX_SLEEP_STOP 2>/dev/null
    magicx_disp_brightness get > "$MAGICX_SLEEP_BRIGHTNESS" 2>/dev/null
    # The darkest raw value: 1, or 255 where the PWM is inverted (MAGICX_BACKLIGHT_REVERSED).
    if [ "$MAGICX_BACKLIGHT_REVERSED" = "1" ]; then _dark=255; else _dark=1; fi
    magicx_disp_brightness set "$_dark" 2>/dev/null
    echo 4 > /sys/class/graphics/fb0/blank 2>/dev/null
}

device_exit_sleep() {
    if [ "$MAGICX_REAL_SLEEP" = "1" ]; then
        magicx_real_exit_sleep
        return
    fi
    echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
    _raw=$(cat "$MAGICX_SLEEP_BRIGHTNESS" 2>/dev/null)
    rm -f "$MAGICX_SLEEP_BRIGHTNESS"
    case "$_raw" in
        ''|*[!0-9]*) _raw=128 ;;
    esac
    magicx_disp_brightness set "$_raw" 2>/dev/null
    killall -q -CONT $MAGICX_SLEEP_STOP 2>/dev/null
    log_message "Left pseudo sleep (brightness raw $_raw)"
}

# The in-game menu composes over a framebuffer snapshot; the panel is portrait and
# the UI rotated, so the capture is un-rotated the way the XX line does it.
take_screenshot() {
    screenshot_path="$1"
    /mnt/SDCARD/spruce/bin64/fbscreenshot "$screenshot_path" -r "${DISPLAY_ROTATION:-0}"
}

# Volume. There is no vendor volume daemon on this base (a133p.sh leaves set_volume
# to the vendor layer), so the codec is driven directly and the level lives in
# 'digital volume' (0..63).
MAGICX_DIGITAL_VOLUME_FLOOR=63
MAGICX_DIGITAL_VOLUME_QUIETEST=41

magicx_apply_volume() {
    vol="${1:-0}"
    case "$vol" in ''|*[!0-9]*) vol=0 ;; esac
    if [ "$vol" -le 0 ]; then
        att=$MAGICX_DIGITAL_VOLUME_FLOOR
    else
        [ "$vol" -gt 20 ] && vol=20
        att=$(( (MAGICX_DIGITAL_VOLUME_QUIETEST * (20 - vol) + 9) / 19 ))
    fi
    amixer sset 'digital volume' "$att" >/dev/null 2>&1
}

set_volume() {
    new_vol="${1:-0}"
    SAVE_TO_CONFIG="${2:-true}"
    [ "$new_vol" -lt 0 ] 2>/dev/null && new_vol=0
    [ "$new_vol" -gt 20 ] 2>/dev/null && new_vol=20
    magicx_apply_volume "$new_vol"
    if [ "$SAVE_TO_CONFIG" = true ]; then
        current_volume=$(jq -r '.vol // 0' "$SYSTEM_JSON" 2>/dev/null)
        [ "$current_volume" = "$new_vol" ] || save_volume_to_config_file "$new_vol"
    fi
}

# One-time mixer state (MinUI's msettings init): headphone gain open, softvol at
# unity. 'DAC volume' is left to the driver; the level itself comes from the json.
magicx_init_audio() {
    amixer sset 'Headphone' 0 >/dev/null 2>&1
    amixer sset 'Soft Volume Master' 255 >/dev/null 2>&1
    magicx_apply_volume "$(get_volume_level 2>/dev/null)"
}

# No RGB LED on these boards (no /sys/class/led_anim): quiet no-ops in place of
# device.sh's "Missing ..." log lines.
enable_or_disable_rgb() {
    log_message "enable_or_disable_rgb: no RGB LED on $PLATFORM" -v
}

rgb_led() {
    log_message "rgb_led: no RGB LED on $PLATFORM" -v
}

# PyUI copies its bundled default into the system json on its first start, but
# runtime.sh reads that file before PyUI runs, so seed it here as Flip.sh does.
magicx_seed_system_json() {
    json="$(get_config_path 2>/dev/null)"
    [ -n "$json" ] && [ ! -f "$json" ] || return 0
    cp /mnt/SDCARD/App/PyUI/main-ui/devices/magicx/magicx-system.json "$json" 2>/dev/null \
        && log_message "MagicX: seeded $json from the bundled default"
}
