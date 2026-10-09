#!/bin/sh
# usb_audio_watchdog.sh - hot-plug watcher for USB sound cards (headsets, DACs)
# on devices where device_usb_audio_supported holds.
#
# asound-setup.sh routes to a USB card only when it runs: at boot, before each
# game, and on Bluetooth changes. This reruns it when the card on hand differs
# from the recorded route, so the menu follows a card plugged in or pulled out;
# a running game keeps its output. The route is re-read on every check rather
# than remembered, which also catches a card that enumerates after the
# boot-time run and a concurrent run that routed from stale state. A run that
# leaves the same mismatch is not repeated until something changes.
#
# Checks run on inotify events: the kernel's devtmpfs creates and removes a
# card's /dev/snd nodes and its remote's /dev/input node, so no udev is needed,
# and the order of those nodes is not fixed. The route file is watched in /tmp
# for runs started elsewhere. Without inotifywait this polls every
# POLL_INTERVAL seconds instead.
#
# It also runs usb_audio_remote.sh on the routed card's own remote, keyed on the
# route as well as the nodes: a replug can bring the same node numbers back.

# shellcheck disable=SC2154 # usb_card and usb_routed are set by device.sh's functions
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

device_usb_audio_supported || exit 0

POLL_INTERVAL="${USB_AUDIO_POLL_INTERVAL:-2}"
REMOTE_READER=/mnt/SDCARD/spruce/scripts/usb_audio_remote.sh
INOTIFYWAIT=/mnt/SDCARD/spruce/bin64/inotifywait
WATCHED="/dev/snd /dev/input /tmp"
EVENTS="/tmp/usb_audio_watchdog.$$"
watcher=""

cleanup() {
    stop_running_watchdog "$REMOTE_READER"
    # Its own watcher only: a restarted watchdog's may already be running.
    [ -n "$watcher" ] && kill "$watcher" 2>/dev/null
    [ -p "$EVENTS" ] && rm -f "$EVENTS"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tried=""
reading="|"   # no route, no remote: the state after the stop below

check() {
    usb_audio_card
    cur="$usb_card"
    usb_audio_read_route
    routed="$usb_routed"
    if [ "$cur" != "$routed" ] && [ "$cur|$routed" != "$tried" ]; then
        log_message "usb_audio_watchdog.sh: USB audio ${cur:-removed}, rerouting"
        # Not the event FIFO as its stdin: a command reading it would eat events.
        /mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME" </dev/null >/dev/null 2>&1
        # What the run left, not what it started from: a run that routed the
        # card leaves no mismatch, so one that reappears later is acted on.
        usb_audio_read_route
        tried="$cur|$usb_routed"
    elif [ "$cur" = "$routed" ]; then
        tried=""
    fi

    usb_audio_read_route
    routed="$usb_routed"
    remote=""
    [ -n "$routed" ] && remote="$(usb_audio_remote "${routed%% *}")"
    if [ "$routed|$remote" != "$reading" ]; then
        stop_running_watchdog "$REMOTE_READER"
        if [ -n "$remote" ]; then
            # shellcheck disable=SC2086 # one argument per input node
            "$REMOTE_READER" $remote &
        fi
        reading="$routed|$remote"
    fi
}

# Create and delete only: every mixer open and close raises CLOSE_WRITE on
# /dev/snd. The route file arrives by a rename into place. The events come
# through a FIFO rather than a pipe, so the loop runs in this shell, where a
# signal interrupts the read, and the watcher's PID is known.
run_event_driven() {
    mkfifo "$EVENTS" || return 1
    # shellcheck disable=SC2086 # one argument per watched directory
    "$INOTIFYWAIT" -m -q -e create -e delete -e moved_to --format '%w%f' $WATCHED > "$EVENTS" 2>/dev/null &
    watcher=$!
    while read -r path; do
        case "$path" in
            /dev/snd/*|/dev/input/*|"$USB_AUDIO_ROUTE") check ;;
        esac
    done < "$EVENTS"
    rm -f "$EVENTS"
}

# Until a card is plugged in, a poll forks nothing but sleep.
run_polling() {
    while :; do
        check
        sleep "$POLL_INTERVAL"
    done
}

stop_running_watchdog "$REMOTE_READER"
check
if [ -x "$INOTIFYWAIT" ]; then
    log_message "usb_audio_watchdog.sh: started, on events"
    run_event_driven
    log_message "usb_audio_watchdog.sh: event loop ended, polling every ${POLL_INTERVAL}s"
else
    log_message "usb_audio_watchdog.sh: started, polling every ${POLL_INTERVAL}s"
fi
run_polling
