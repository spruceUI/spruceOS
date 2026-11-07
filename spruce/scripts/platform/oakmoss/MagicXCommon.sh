#!/bin/sh

# The MagicX boards (Mini Zero 28, Zero 40, XU20 V32) on oakMOSS (oakMOSSCommon.sh): what the three share as
# MagicX boards, the simplepad pad and its RetroArch profiles, the codec's mixer, the work LED. Their own
# differences live in Zero28.sh, Zero40.sh, XU20.sh and their platform cfgs.

. "/mnt/SDCARD/spruce/scripts/platform/oakmoss/oakMOSSCommon.sh"

# Resolve the input nodes at boot instead of trusting the cfg's numbering: they
# enumerate in whatever order the drivers probe. The cfg values stay as fallbacks.
oakmoss_resolve_event_paths() {
    # The simplepad driver (UART MCU pad) registers its input device as
    # "magicx-input" (strings in simplepad.ko), not under the generic names.
    pad=$(oakmoss_find_event_by_name "*magicx-input*" "*magicx*" "*simplepad*" "*[Gg]amepad*" "*[Jj]oystick*" "*joypad*")
    if [ -n "$pad" ]; then
        export EVENT_PATH_SEND_TO_DRASTIC="$pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$pad"
        export EVENT_PATH_READ_INPUTS_SPRUCE="$pad"
        export EVENT_PATH_VOLUME="$pad"
    fi
    pwr=$(oakmoss_find_event_by_name "*axp*pek*" "*[Pp]ower*" "*pwr*")
    [ -n "$pwr" ] && export EVENT_PATH_POWER="$pwr"
    if [ "$DEVICE_HAS_TOUCHSCREEN" = "true" ]; then
        t=$(oakmoss_touch_event_path) && export EVENT_PATH_TOUCH="$t"
    fi
    log_message "MagicX input nodes: pad=${EVENT_PATH_READ_INPUTS_SPRUCE} power=${EVENT_PATH_POWER} touch=${EVENT_PATH_TOUCH:-none}"
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

# One-time mixer state (MinUI's msettings init): headphone gain open, softvol at
# unity. 'DAC volume' is left to the driver; the level itself comes from the json.
oakmoss_init_audio() {
    amixer sset 'Headphone' 0 >/dev/null 2>&1
    amixer sset 'Soft Volume Master' 255 >/dev/null 2>&1
    oakmoss_apply_volume "$(get_volume_level 2>/dev/null)"
}

# The work LED is a MagicX pin, written through the whole PB data register (utils/magicx/led.sh), so only
# this tier has it: the other oakMOSS boards keep common64bit.sh's stubs and never touch port B.
work_led_off() {
    /mnt/SDCARD/spruce/scripts/platform/utils/magicx/led.sh off
}

work_led_on() {
    /mnt/SDCARD/spruce/scripts/platform/utils/magicx/led.sh on
}
