#!/bin/sh

# The route asound-setup.sh records: line 1 is the card as usb_audio_card sets
# it, line 2 its volume control (may be empty). Absent when not routed to USB.
USB_AUDIO_ROUTE=/tmp/usb_audio_route

# Arg1: the card as usb_audio_card sets it, or nothing to clear the route.
# Arg2: its volume control. Written whole, as PyUI and the volume keys read it
# at any time.
usb_audio_record_route() {
    if [ -z "$1" ]; then
        [ -e "$USB_AUDIO_ROUTE" ] && rm -f "$USB_AUDIO_ROUTE"
        return 0
    fi
    printf '%s\n%s\n' "$1" "$2" > "$USB_AUDIO_ROUTE.$$" &&
        mv "$USB_AUDIO_ROUTE.$$" "$USB_AUDIO_ROUTE"
}

# Sets usb_routed (the card as usb_audio_card sets it) and usb_routed_control;
# both empty, and status 1, when not routed. Builtins only, as it runs on every
# volume step and every watchdog poll.
usb_audio_read_route() {
    usb_routed=""
    usb_routed_control=""
    [ -s "$USB_AUDIO_ROUTE" ] || return 1
    { read -r usb_routed; read -r usb_routed_control; } < "$USB_AUDIO_ROUTE"
}

# The sysfs path of the USB device a sound card belongs to: the parent of its
# audio interface. Arg1: card.
usb_audio_usb_device() {
    _intf="$(readlink -f "/sys/class/sound/card$1/device" 2>/dev/null)"
    [ -n "$_intf" ] && echo "${_intf%/*}"
}

# The input nodes of one class ("event", "js") on a USB device, space separated.
# Arg1: the device's sysfs path. Arg2: the class.
usb_audio_inputs() {
    [ -n "$1" ] || return 0
    _nodes=""
    for _in in /sys/class/input/"$2"[0-9]*; do
        case "$(readlink -f "$_in/device" 2>/dev/null)" in
            "$1"/*) _nodes="$_nodes /dev/input/${_in##*/}" ;;
        esac
    done
    echo "${_nodes# }"
}

# Sets usb_card to the first USB card that can play, as "<card> <device>
# <usbbus>", or empty with status 1. A microphone has no Playback section in its
# streamN. A gamepad with a headset jack registers a card too, so a card whose
# USB device also has a joystick is skipped. usbbus changes on every enumeration,
# so a replugged card differs at the same index. Polled by usb_audio_watchdog.sh:
# with no USB card present it runs builtins only.
# shellcheck disable=SC2034 # usb_card is for the caller
usb_audio_card() {
    usb_card=""
    for _dir in /proc/asound/card[0-9]*; do
        [ -e "$_dir/usbid" ] || continue
        _card="${_dir##*/card}"
        for _stream in "$_dir"/stream[0-9]*; do
            grep -q '^Playback:' "$_stream" 2>/dev/null || continue
            [ -n "$(usb_audio_inputs "$(usb_audio_usb_device "$_card")" js)" ] && break
            _bus=""
            read -r _bus < "$_dir/usbbus" 2>/dev/null
            usb_card="$_card ${_stream##*/stream} $_bus"
            return 0
        done
    done
    return 1
}

# The card's playback volume control, found by capability because headsets name
# it after themselves. A control named for the microphone is never taken: a "Mic"
# with playback volume is the sidetone, and alsa-lib lists it ahead of unknown
# names. A playback-only control is preferred, and one that also captures is the
# fallback, as some headsets have only that.
usb_audio_volume_control() {
    amixer -c "$1" scontents 2>/dev/null | awk '
        /^Simple mixer control / { sub(/^Simple mixer control /, ""); name = $0; next }
        name != "" && /^ *Capabilities:/ {
            play = 0; capture = 0
            for (i = 2; i <= NF; i++) {
                if ($i == "pvolume" || $i == "volume") play = 1
                if ($i ~ /^c(volume|switch)/) capture = 1
            }
            if (play && tolower(name) !~ /mic|sidetone|monitor|capture/) {
                if (!capture) { print name; found = 1; exit }
                if (fallback == "") fallback = name
            }
            name = ""
        }
        END { if (!found && fallback != "") print fallback }'
}

# Arg1: card. Arg2: level 0-20. Arg3: the control, if known. Raw ranges differ
# per device, so the level is a share of the range, and 0 also mutes where the
# control has a switch. Writes name playback, or amixer moves a combined
# control's capture side, the microphone gain, too.
usb_audio_set_volume() {
    _ctl="${3:-$(usb_audio_volume_control "$1")}"
    [ -n "$_ctl" ] || return 0
    _lvl="${2:-0}"
    amixer -q -c "$1" sset "$_ctl" playback "$((_lvl * 5))%" >/dev/null 2>&1
    if [ "$_lvl" -gt 0 ]; then
        amixer -q -c "$1" sset "$_ctl" playback unmute >/dev/null 2>&1
    else
        amixer -q -c "$1" sset "$_ctl" playback mute >/dev/null 2>&1
    fi
    return 0
}

# The input nodes of a card's own remote (inline buttons, a crown): every input
# device on its USB device, since some split their keys across nodes. Arg1: card.
usb_audio_remote() {
    usb_audio_inputs "$(usb_audio_usb_device "$1")" event
}

# Arg1: level 0-20, applied to the routed USB card, if any.
usb_audio_follow_volume() {
    usb_audio_read_route || return 0
    [ -n "$usb_routed_control" ] || return 0
    usb_audio_set_volume "${usb_routed%% *}" "$1" "$usb_routed_control"
}
