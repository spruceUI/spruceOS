#!/bin/sh

# Powkiddy V90S and V20 on oakMOSS: the Powkiddy boards' layer. Everything comes from the oakMOSS
# base (oakMOSSCommon.sh, our Tina on SD1) except what differs on these boards: the pad
# (oakMOSS's adc-joypad, named per board), the volume keys on their own LRADC device, the
# RetroArch pad profiles, the rumble, the speaker route and WiFi, which is a USB dongle or nothing.

. "/mnt/SDCARD/spruce/scripts/platform/oakmoss/oakMOSSCommon.sh"

get_config_path() {
    echo "$SYSTEM_JSON"
}

# No onboard radio (the RG28XX's shape): there is a radio while a supported USB dongle is on the
# bus, so wifi.sh's status, and with it PyUI's WiFi menu, follows the bus.
device_has_wifi_radio() {
    usb_wifi_dongle_present >/dev/null 2>&1
}

# The pad by its board name (POWKIDDY_PAD_NAME, from the cfg), the volume keys on the LRADC,
# the AXP2202 power key. These boards have no touch panel.
oakmoss_resolve_event_paths() {
    pad=$(oakmoss_find_event_by_name "$POWKIDDY_PAD_NAME" "*[Gg]amepad*" "*joypad*")
    if [ -n "$pad" ]; then
        export EVENT_PATH_SEND_TO_DRASTIC="$pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$pad"
        export EVENT_PATH_READ_INPUTS_SPRUCE="$pad"
    fi
    vol=$(oakmoss_find_event_by_name "sunxi-keyboard" "*keyboard*")
    [ -n "$vol" ] && export EVENT_PATH_VOLUME="$vol"
    pwr=$(oakmoss_find_event_by_name "*axp*pek*" "*[Pp]ower*" "*pwr*")
    [ -n "$pwr" ] && export EVENT_PATH_POWER="$pwr"
    log_message "Powkiddy input nodes: pad=${EVENT_PATH_READ_INPUTS_SPRUCE} volume=${EVENT_PATH_VOLUME} power=${EVENT_PATH_POWER}"
}

# Each board's pad has a name of its own, so RetroArch's profiles for them sit in
# .retroarch/autoconfig/sdl2 as shipped: nothing to stage.
stage_ra_autoconfig() {
    return 0
}

# The speaker sits behind the codec's LINEOUT, which Knulli switches on for these two boards
# alone (its S00audio-setup); the codec drives the amplifier pin (PH6) itself.
oakmoss_init_audio() {
    amixer sset 'Headphone' 0 >/dev/null 2>&1
    amixer sset 'Soft Volume Master' 255 >/dev/null 2>&1
    amixer sset 'LINEOUT' on >/dev/null 2>&1
    oakmoss_apply_volume "$(get_volume_level 2>/dev/null)"
}

# The V90S's motor hangs off the pad as force feedback (PWM2); the V20 has none, which its
# pad reports as no FF bits. Same call shape and starting magnitudes as AnbernicXXCommon.sh:
# untuned on this motor.
powkiddy_pad_has_ff() {
    _ff=$(cat "/sys/class/input/${EVENT_PATH_READ_INPUTS_SPRUCE##*/}/device/capabilities/ff" 2>/dev/null)
    [ -n "$(echo "$_ff" | tr -d ' 0')" ]
}

vibrate() {
    duration=150
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"
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
    powkiddy_pad_has_ff || return 0
    case "$intensity" in
        "Weak")   intensity=0x8000 ;;
        "Medium") intensity=0xC000 ;;
        "Strong") intensity=0xFFFF ;;
    esac
    [ -x /mnt/SDCARD/spruce/bin64/rumble ] || return 0
    /mnt/SDCARD/spruce/bin64/rumble "$EVENT_PATH_READ_INPUTS_SPRUCE" "$intensity" "$duration"
}
