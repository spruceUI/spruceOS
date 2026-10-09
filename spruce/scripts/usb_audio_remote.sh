#!/bin/sh
# usb_audio_remote.sh <input node>... - the volume buttons on a USB headset's own
# remote, which no other watchdog reads: they register as an input device of
# their own, and buttons_watchdog.sh reads a fixed list of nodes.
#
# Started and stopped by usb_audio_watchdog.sh for the card audio is routed to.
# A press steps the volume through the device's volume_up/volume_down, so the
# card, the codec and the level stored for the UI move together. A held button
# autorepeats; that steps at most every 0.3 s, the pace of buttons_watchdog.sh.
# Exits when the nodes go away.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

[ $# -gt 0 ] || { echo "usage: usb_audio_remote.sh <input node>..." >&2; exit 2; }
REPEAT_CS=30
last=0

# Arg1: press or repeat. Arg2: the function to run.
step() {
    now="$(cut -d ' ' -f 1 /proc/uptime | tr -d .)"
    if [ "$1" = repeat ] && [ $((now - last)) -lt "$REPEAT_CS" ]; then
        return 0
    fi
    last="$now"
    "$2"
}

log_message "usb_audio_remote.sh: reading $*"
getevent "$@" | while read -r line; do
    case "$line" in
        *"key 1 115 1"*) step press volume_up ;;
        *"key 1 115 2"*) step repeat volume_up ;;
        *"key 1 114 1"*) step press volume_down ;;
        *"key 1 114 2"*) step repeat volume_down ;;
    esac
done
log_message "usb_audio_remote.sh: $* closed"
