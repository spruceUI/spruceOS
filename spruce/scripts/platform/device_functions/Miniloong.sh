#!/bin/sh
# Miniloong Pocket 1 device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/dArkMossCommon.sh"

# The radio is attached by the kernel (hci0 exists from boot); dArkMossCommon's
# device_bluetooth_up/down start and stop bluetoothd and bluealsa.
device_bluetooth_supported() {
    return 0
}

# The jack is the extcon named rk-headset; its index follows probe order.
are_headphones_plugged_in() {
    for _x in /sys/class/extcon/*; do
        [ "$(cat "$_x/name" 2>/dev/null)" = "rk-headset" ] || continue
        grep -q 'HEADPHONE=1' "$_x/state" 2>/dev/null
        return
    done
    return 1
}

# The DC port reports as usb, not ac; the data port does not charge.
device_get_charging_status() {
    if [ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" = "1" ]; then
        if [ "$(cat "$BATTERY/capacity" 2>/dev/null)" = "100" ]; then
            echo "Full"
        else
            echo "Charging"
        fi
    else
        echo "Discharging"
    fi
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e $EVENT_PATH_READ_INPUTS_SPRUCE"
}

  ###################
#####   RGB LED   #####
  ###################

# One ring around the stick, an AW20036 behind a patched driver that takes
# eight named colours and five effects. dArkMoss runs its own battery LED
# daemon on it at boot and again after every wake; spruce stops that and
# drives the ring from the RGB LED settings.

MINILOONG_LED="/sys/class/leds/aw20036_led"
MINILOONG_LED_STATE="/tmp/miniloong_rgb_state"

has_rgb_leds() {
    [ -w "$MINILOONG_LED/miniloong_color" ]
}

miniloong_led_take() {
    systemctl is-active --quiet miniloong_led 2>/dev/null && systemctl stop miniloong_led 2>/dev/null
}

miniloong_led_write() {
    echo "$2" > "$MINILOONG_LED/$1" 2>/dev/null
}

# Nearest of the driver's named colours to the hex.
miniloong_led_colour() {
    _hex="$1"
    case "$_hex" in
        [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
        *) _hex=FFFFFF ;;
    esac
    _rest="${_hex#??}"
    _r=$((0x${_hex%????})) _g=$((0x${_rest%??})) _b=$((0x${_rest#??}))
    [ $((_r + _g + _b)) -lt 48 ] && { echo off; return; }
    _best=white _bestd=999999
    for _c in "red 255 0 0" "yellow 255 255 0" "green 0 255 0" "cyan 0 255 255" \
              "blue 0 0 255" "magenta 255 0 255" "white 255 255 255"; do
        set -- $_c
        _d=$(( (_r - $2) * (_r - $2) + (_g - $3) * (_g - $3) + (_b - $4) * (_b - $4) ))
        [ "$_d" -lt "$_bestd" ] && { _bestd=$_d; _best=$1; }
    done
    echo "$_best"
}

# rise and sniff have no equivalent and land on solid.
miniloong_led_effect() {
    case "$1" in
        0|off|disable) echo off ;;
        2|breath*)     echo breathe ;;
        5|6|7|blink*)  echo blink ;;
        rainbow*)      echo rainbow ;;
        *)             echo solid ;;
    esac
}

# Shares the TrimUI's 5-80 setting, spread over the driver's 0-255.
miniloong_led_brightness() {
    _scale="$(get_config_value '.menuOptions."RGB LED Settings".LEDmaxScale.selected' "15")"
    case "$_scale" in ''|*[!0-9]*) _scale=15 ;; esac
    [ "$_scale" -gt 80 ] && _scale=80
    echo $(( _scale * 255 / 80 ))
}

# The rate units are the driver's; these scalings are a first guess from its
# defaults (breathe 30, rainbow 120) and tune by feel.
miniloong_led_apply() {
    _col="$1" _eff="$2" _dur="$3"
    _bri="$(miniloong_led_brightness)"
    _state="$_col $_eff $_dur $_bri"
    [ "$_state" = "$(cat "$MINILOONG_LED_STATE" 2>/dev/null)" ] && return 0
    echo "$_state" > "$MINILOONG_LED_STATE"

    miniloong_led_take
    miniloong_led_write trigger none
    miniloong_led_write miniloong_brightness "$_bri"
    case "$_eff" in
        blink)   miniloong_led_write miniloong_blink_rate "$((_dur / 2)) $((_dur / 2))" ;;
        breathe) miniloong_led_write miniloong_breathe_rate "$((_dur / 100))" ;;
        rainbow) miniloong_led_write miniloong_rainbow_rate "$((_dur / 25))" ;;
    esac
    if [ "$_eff" = off ] || [ "$_col" = off ]; then
        miniloong_led_write miniloong_effect solid
        miniloong_led_write miniloong_color off
    else
        miniloong_led_write miniloong_color "$_col"
        miniloong_led_write miniloong_effect "$_eff"
    fi
}

# Zones are ignored: there is one ring.
rgb_led() {
    has_rgb_leds || return 0
    rgb_leds_enabled || return 0
    flag_check "leds_forced_off" && return 0

    _dur="${4:-1000}"
    case "$_dur" in ''|*[!0-9]*) _dur=1000 ;; esac
    _eff="$(miniloong_led_effect "$2")"
    if [ "$_eff" = off ]; then
        _col=off
    else
        _col="$(miniloong_led_colour "${3:-FFFFFF}")"
    fi
    miniloong_led_apply "$_col" "$_eff" "$_dur"
}

enable_or_disable_rgb() {
    has_rgb_leds || return 0
    miniloong_led_take
    if ! rgb_leds_enabled; then
        miniloong_led_apply off off 1000
    fi
}

toggle_led() {
    has_rgb_leds || return 0
    if flag_check "leds_forced_off"; then
        flag_remove "leds_forced_off"
        set_rgb_in_menu
    else
        rgb_led lr off
        flag_add "leds_forced_off" --tmp
    fi
}

# The base's wake hook restarts its LED daemon in the background a moment
# after resume, so retake the ring after it has done so.
miniloong_led_restore() {
    has_rgb_leds || return 0
    (
        sleep 3
        rm -f "$MINILOONG_LED_STATE"
        enable_or_disable_rgb
        set_rgb_in_menu
    ) >/dev/null 2>&1 &
}

device_exit_sleep() {
    darkmoss_exit_sleep
    miniloong_led_restore
}

device_prepare_for_poweroff() {
    darkmoss_prepare_for_poweroff
    has_rgb_leds && miniloong_led_apply off off 1000
}
