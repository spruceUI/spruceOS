#!/bin/sh
# GameMT E5 Plus device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/darkmoss/dArkMossCommon.sh"

# No device_bluetooth_supported override: device.sh's default (unsupported)
# stands. The radio is an RTL8733BS; dArkMoss loads its Bluetooth firmware
# (RTL8723F core), but powering the controller on still fails, so the menu
# would only offer a scan that never finds anything.

# The jack switch's live level (GPIO4_C6, high = plugged), the same source as
# dArkMoss's e5plus-jackd: rk_headset's extcon misses bounced insertions, and a
# stale "out" here made spruce put the speaker back on every volume change.
are_headphones_plugged_in() {
    _l="$(grep 'headset_gpio' /sys/kernel/debug/gpio 2>/dev/null)"
    if [ -n "$_l" ]; then
        case "$_l" in *" hi"*) return 0 ;; *) return 1 ;; esac
    fi
    for _x in /sys/class/extcon/*; do
        [ "$(cat "$_x/name" 2>/dev/null)" = "rk-headset" ] || continue
        grep -q 'HEADPHONE=1' "$_x/state" 2>/dev/null
        return
    done
    return 1
}

# spruce's idle timers (idlemon) count gamepad events as activity only when
# told the pad's node; without this they watch nothing useful and fire on a
# timer however much the device is being used.
set_event_arg_for_idlemon() {
    EVENT_ARG="-e $EVENT_PATH_READ_INPUTS_SPRUCE"
}

rgb_led() {
    [ -n "$6" ] && echo "$6" > "$LED_PATH/trigger"
    return 0
}

work_led_off() {
    echo 0 >"${LED_PATH}/brightness"
}

work_led_on() {
    echo 1 >"${LED_PATH}/brightness"
}

vibrate() {
    e5plus_blink_led &
    darkmoss_vibrate "$@"
}

# Blink, then leave the LED as it was (the button backlights may be off).
e5plus_blink_led() {
    _was="$(cat "${LED_PATH}/brightness" 2>/dev/null)"
    for _i in 0 1 2 ; do
        work_led_off
        sleep 0.08
        work_led_on
        sleep 0.08
    done
    [ "$_was" = "0" ] && work_led_off
}

# The common kmsgrab capture saves the panel's raw scanout, which on this
# 720x1280 portrait panel is the picture turned 90 degrees clockwise (the
# system SDL rotates DSI output with RGA ROT_90). Turn it back so the Game
# Switcher shows it upright. HDMI output is not rotated, so leave it alone there.
take_screenshot() {
    screenshot_path="$1"
    [ -n "$screenshot_path" ] || return 1
    _ff=""
    for _c in /mnt/SDCARD/spruce/bin/ffmpeg /usr/bin/ffmpeg; do
        [ -x "$_c" ] && { _ff="$_c"; break; }
    done
    [ -n "$_ff" ] || {
        log_message "take_screenshot: no ffmpeg with kmsgrab available"
        return 1
    }
    mkdir -p "$(dirname "$screenshot_path")" 2>/dev/null

    _vf="hwdownload,format=bgr0,format=rgba"
    grep -q '^connected' "$HDMI_STATE_PATH" 2>/dev/null || _vf="$_vf,transpose=2"

    if timeout 15 "$_ff" -hide_banner -loglevel error \
        -f kmsgrab -i - \
        -vf "$_vf" \
        -frames:v 1 -update 1 -y "$screenshot_path" >/dev/null 2>&1; then
        return 0
    fi

    rm -f "$screenshot_path" 2>/dev/null
    log_message "take_screenshot: kmsgrab capture failed"
    return 1
}

# On wake, put the backlight back at the user's level. The base's sleep hook
# restores whatever the panel showed when sleep began, which is PyUI's
# screensaver dim if the device dozed off from the menu - hence the
# "sometimes dim after waking". This runs after systemd-suspend finishes
# (trigger_device_sleep waits for it), so it has the last word.
device_exit_sleep() {
    darkmoss_exit_sleep
    apply_backlight "$(get_backlight_level)"
}

# The light rings round both sticks, from Settings > RGB LED Settings > RGB
# LEDs, as on the RG40XXH (off by default). They are plain on/off gpio-leds, so
# only the on/off setting applies. Through dArkMoss's e5plus-lights helper when
# present, so its boot-time restore and charging screen agree with the setting.
E5PLUS_LIGHTS_HELPER="/usr/local/bin/e5plus-lights.sh"

has_rgb_leds() {
    [ -w /sys/class/leds/left_joystick/brightness ]
}

enable_or_disable_rgb() {
    has_rgb_leds || return 0
    if rgb_leds_enabled; then _mode=on; _val=1; else _mode=sticks-off; _val=0; fi
    if [ -f "$E5PLUS_LIGHTS_HELPER" ]; then
        sh "$E5PLUS_LIGHTS_HELPER" "$_mode" >/dev/null 2>&1 && return 0
    fi
    for _l in left_joystick right_joystick; do
        echo "$_val" > "/sys/class/leds/$_l/brightness" 2>/dev/null
    done
}
