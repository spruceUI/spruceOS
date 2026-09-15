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
    pad=$(magicx_find_event_by_name "*simplepad*" "*[Gg]amepad*" "*[Jj]oystick*" "*joypad*")
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

device_init() {
    runtime_mounts_magicx

    export LD_LIBRARY_PATH="/usr/magicx/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib"

    init_gpio_a133p
    magicx_resolve_event_paths

    (
        syslogd -S
        hwclock -s -u
    ) &
    # Bluetooth: the base ships bluez and the XR829 BT firmware, but the HCI attach
    # sequence is not wired on this family yet; PyUI's Bluetooth toggle owns it.
    amixer set 'Soft Volume Master' 255 2>/dev/null

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash 2>/dev/null
        chmod +x /bin/bash 2>/dev/null
    fi
}

# MinUI's zero28 port found some board revisions keep the panel dark after a
# resume unless the backlight is driven low and back to its level; the wake-up
# below does that first, then the inherited A133P radio bring-up.
magicx_relight_panel() {
    level=$(jq -r '.backlight // 5' "$SYSTEM_JSON" 2>/dev/null)
    case "$level" in ''|*[!0-9]*) level=5 ;; esac
    [ "$level" -ge 1 ] || level=5
    set_backlight 1
    set_backlight "$level"
}

device_exit_sleep() {
    magicx_relight_panel
    clear_wake_alarm "$WAKE_ALARM_PATH"
    if usb_wifi_wait_after_resume; then
        wifi_request apply --wait
        return 0
    fi
    modprobe xradio_wlan
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON" 2>/dev/null)" = 1 ]; then
        for _ in 1 2 3 4 5; do
            ip link show wlan0 >/dev/null 2>&1 && break
            sleep 1
        done
    fi
    wifi_request apply --wait
}
