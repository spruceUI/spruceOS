#!/bin/sh

# MagicX A133P family: Mini Zero 28 and Zero 40.
#
# Same Allwinner A133P as the TrimUI Smart Pro / Brick, so everything that is
# SoC-generic (sleep and wake, WiFi through the XR829 driver, rumble, volume,
# the /dev/disp backlight) is inherited from trimui_a133p.sh. What differs is
# the base OS: these boards run our own pared-down Tina Linux on SD1
# (CFW/Spruce/devices in the wrapper, Moss-zero28's lineage) instead of TrimUI's
# firmware, so there are no /usr/trimui blobs (no trimui_inputd: the kernel's
# simplepad driver is the gamepad), the SDL2 blobs live in /usr/magicx/lib, and
# the image names the model in /usr/magicx/device.
#
# Intended to be sourced by Zero28.sh / Zero40.sh only.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_a133p.sh"

# zero28 | zero40, from the base image's marker. Images without one predate
# the marker and are Zero 28 (Moss-zero28 itself).
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
    magicx_find_event_by_name "*[Tt]ouch*" "*ts*" "*gt9*" "*ft5*" "*goodix*" "*[Ff]ocal*"
}

init_gpio_a133p() {
    #PD11 pull high for VCC-5v
    echo 107 > /sys/class/gpio/export
    printf '%s' out > /sys/class/gpio/gpio107/direction
    printf '%s' 1 > /sys/class/gpio/gpio107/value

    #rumble motor PH3
    echo 227 > /sys/class/gpio/export
    printf '%s' out > /sys/class/gpio/gpio227/direction
    printf '%s' 0 > /sys/class/gpio/gpio227/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    printf '%s' in > /sys/class/gpio/gpio243/direction
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

# Resolve the input nodes at boot instead of trusting the cfg's numbering: the
# simplepad gamepad, the PMIC power key and (Zero 40) the touchscreen enumerate
# in whatever order the drivers probe. The cfg values stay as fallbacks.
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
    for _other in 8189es xradio_wlan; do
        [ "$_other" = "$WIFI_ONBOARD_MODULE" ] && continue
        usb_wifi_module_loaded "$_other" && rmmod "$_other" 2>/dev/null
    done
    mkdir -p "$(dirname "$MAGICX_RADIO_KMSG")" 2>/dev/null
    cat /dev/kmsg > "$MAGICX_RADIO_KMSG" 2>/dev/null &
    _kmsg_pid=$!
    modprobe "$WIFI_ONBOARD_MODULE" 2>/tmp/magicx_radio_err; rc=$?
    for _ in 1 2 3 4 5; do
        [ -d /sys/class/net/wlan0 ] && break
        sleep 1
    done
    kill "$_kmsg_pid" 2>/dev/null
    sync
    log_message "MagicX radio: modprobe $WIFI_ONBOARD_MODULE rc=$rc $(head -1 /tmp/magicx_radio_err 2>/dev/null); wlan0=$([ -d /sys/class/net/wlan0 ] && echo yes || echo no); sdio=$(ls /sys/bus/sdio/devices 2>/dev/null | tr '\n' ' '); $(grep -a -i 'xradio\|sbus\|RTW: \|8189\|firmware\|sdd\|Unable to handle\|BUG' "$MAGICX_RADIO_KMSG" 2>/dev/null | head -8 | cut -c1-160 | tr '\n' '|')"
    return 0
}

device_init() {
    runtime_mounts_magicx
    magicx_disown_base_supplicant
    magicx_seed_system_json

    export LD_LIBRARY_PATH="/usr/magicx/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib"

    init_gpio_a133p
    magicx_resolve_event_paths
    magicx_load_onboard_radio

    (
        syslogd -S
        hwclock -s -u
    ) &
    # Bluetooth: the base ships bluez and the XR829 BT firmware, but the HCI attach
    # sequence is not wired on this family yet; PyUI's Bluetooth toggle owns it.
    magicx_init_audio

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash 2>/dev/null
        chmod +x /bin/bash 2>/dev/null
    fi
}

# MinUI's zero28 port found some board revisions keep the panel dark after a
# resume unless the backlight is driven low and back to its level.

# Battery. The AXP2202 gauge read 0-1 % on a healthy cell (Zero 40), so a low
# reading with a good voltage becomes an estimate and holds the shutdown off.
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
    if [ "$cap" -le 1 ]; then
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

magicx_relight_panel() {
    level=$(jq -r '.backlight // 5' "$SYSTEM_JSON" 2>/dev/null)
    case "$level" in ''|*[!0-9]*) level=5 ;; esac
    [ "$level" -ge 1 ] || level=5
    set_backlight 1
    set_backlight "$level"
}

# Sleep: the onboard radio here is the Realtek 8189es (WIFI_ONBOARD_MODULE), not
# trimui_a133p.sh's XR829, so that is the module that goes out before suspend.
device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    wifi_request suspend --wait
    usb_wifi_note_sleep
    usb_wifi_tear_down
    usb_wifi_module_loaded "$WIFI_ONBOARD_MODULE" && rmmod "$WIFI_ONBOARD_MODULE"
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

device_exit_sleep() {
    magicx_relight_panel
    clear_wake_alarm "$WAKE_ALARM_PATH"
    if usb_wifi_wait_after_resume; then
        wifi_request apply --wait
        return 0
    fi
    modprobe "$WIFI_ONBOARD_MODULE"
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON" 2>/dev/null)" = 1 ]; then
        for _ in 1 2 3 4 5; do
            ip link show wlan0 >/dev/null 2>&1 && break
            sleep 1
        done
    fi
    wifi_request apply --wait
}

# The in-game menu composes over a framebuffer snapshot; the panel is portrait and
# the UI rotated, so the capture is un-rotated the way the XX line does it.
take_screenshot() {
    screenshot_path="$1"
    /mnt/SDCARD/spruce/bin64/fbscreenshot "$screenshot_path" -r "${DISPLAY_ROTATION:-0}"
}

# Volume. trimui_a133p.sh's set_volume writes a file only TrimUI's daemon reads, so
# the codec is driven directly and the level lives in 'digital volume' (0..63).
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

# TrimUI-only hooks inherited from trimui_a133p.sh. The MagicX boards have no
# /sys/class/led_anim, so the RGB hooks are no-ops here.
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
