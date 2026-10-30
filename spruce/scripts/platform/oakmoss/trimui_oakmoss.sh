#!/bin/sh

# TrimUI's A133P boards on oakMOSS (our Tina on TrimUI's untouched boot chain), in place of trimui_a133p.sh:
# the oakMOSS A133P base, plus the TrimUI names the board files call. Of TrimUI's userland only trimui_inputd
# is there (oakMOSS starts it).

. "/mnt/SDCARD/spruce/scripts/platform/oakmoss/oakmoss_a133p.sh"

# oakMOSS runs TrimUI's own trimui_inputd (/etc/init.d/trimui-inputd), so the pad is "TRIMUI Player1"
# as on stock, the volume keys included; the LRADC keyboard sends nothing on the Brick. The AXP2202
# power key.
magicx_resolve_event_paths() {
    pad=$(magicx_find_event_by_name "TRIMUI Player1" "TRIMUI*")
    if [ -n "$pad" ]; then
        export EVENT_PATH_SEND_TO_DRASTIC="$pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$pad"
        export EVENT_PATH_READ_INPUTS_SPRUCE="$pad"
        export EVENT_PATH_VOLUME="$pad"
    fi
    pwr=$(magicx_find_event_by_name "*axp*pek*" "*[Pp]ower*" "*pwr*")
    [ -n "$pwr" ] && export EVENT_PATH_POWER="$pwr"
    log_message "TrimUI on oakMOSS input nodes: pad=${EVENT_PATH_READ_INPUTS_SPRUCE} power=${EVENT_PATH_POWER}"
}

# RetroArch takes the pad from retroarch-<PLATFORM>.cfg's binds, as on stock: nothing to stage.
stage_ra_autoconfig() {
    return 0
}

# The board's own PyUI default (devices/trimui/brick-system.json), not the MagicX one: the base's
# init seeds the file before PyUI first starts.
magicx_seed_system_json() {
    json="$(get_config_path 2>/dev/null)"
    [ -n "$json" ] && [ ! -f "$json" ] || return 0
    cp "/mnt/SDCARD/App/PyUI/main-ui/devices/trimui/${TRIMUI_DEFAULT_SYSTEM_JSON:-brick-system.json}" "$json" 2>/dev/null \
        && log_message "TrimUI on oakMOSS: seeded $json from the bundled default"
}

# The base's mixer setup, plus what the stock firmware does for the speaker where this kernel has it
# (the stock speaker-mute switch; the codec's LINEOUT). The control list goes to the log once: the
# speaker path on this kernel is not measured yet.
magicx_init_audio() {
    amixer sset 'Headphone' 0 >/dev/null 2>&1
    amixer sset 'Soft Volume Master' 255 >/dev/null 2>&1
    amixer sset 'LINEOUT' on >/dev/null 2>&1
    [ -w /sys/class/speaker/mute ] && echo 0 > /sys/class/speaker/mute
    magicx_apply_volume "$(get_volume_level 2>/dev/null)"
    [ -e /tmp/trimui_oakmoss_mixer_logged ] || {
        log_message "TrimUI on oakMOSS mixer: $(amixer scontrols 2>&1 | sed -n "s/^Simple mixer control '\(.*\)',.*/\1/p" | tr '\n' '|')"
        touch /tmp/trimui_oakmoss_mixer_logged
    }
}

# The TrimUI line's Fn switch is PH19 (gpio243), a pad button on MagicX, whose layer silences this.
device_get_switch_position() {
    cat /sys/class/gpio/gpio243/value 2>/dev/null
}

# MagicX's work LED is a raw PB data-register write; no PB pin is an output on the Brick, whose LEDs
# are TrimUI's RGB zones (not driven on oakMOSS yet).
work_led_on() {
    log_message "work_led_on: no work LED on $PLATFORM" -v
}

work_led_off() {
    log_message "work_led_off: no work LED on $PLATFORM" -v
}

device_init_a133p() {
    magicx_device_init
}

# a133p.sh's set, without TrimUI's volume sync: no stock daemon writes /tmp/system/set_volume here,
# the volume keys go through buttons_watchdog.sh and set_volume above.
launch_trimui_startup_watchdogs() {
    launch_common_startup_watchdogs_v2

    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}

    stop_running_watchdog /mnt/SDCARD/spruce/scripts/usb_wifi_watchdog.sh
    if [ -n "$WIFI_USB_MODULES_DIR" ]; then
        /mnt/SDCARD/spruce/scripts/usb_wifi_watchdog.sh &
        pin_cpu "$SYSTEM_CPU" -n usb_wifi_watchdog.sh &
    fi
}
