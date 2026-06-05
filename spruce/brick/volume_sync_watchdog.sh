#!/bin/sh
# Mirror the firmware volume value into spruce's stored volume so the in-UI
# volume bar tracks the hardware Volume +/- keys, including while held.
#
# On the Brick the physical volume keys are handled by the stock firmware
# (trimui_inputd/hardwareservice), which owns /tmp/system/set_volume: it writes
# the new level there on every key event (autorepeat included) and applies it to
# ALSA and to its own config (/mnt/UDISK/system.json). spruce never read that
# file back, so its own .vol (SYSTEM_JSON) only changed when spruce itself set
# the volume. The UI volume bar reads .vol, so holding a volume key moved the
# audio but not the bar (it updated once at most, never ramped).
#
# This watchdog reacts to writes of /tmp/system/set_volume and mirrors the value
# into SYSTEM_JSON, the file PyUI's config watcher polls to redraw the bar. That
# is the watchdog's whole job: the durable copy and ALSA are the firmware's, so
# we deliberately do NOT call set_volume here (it would just re-poke the
# firmware's command file and add a redundant synchronous flash write). Keeping
# to a single in-place edit of SYSTEM_JSON is what lets the bar chase the OSD
# instead of crawling behind it while a key is held.
#
# Events are delivered by inotifywait so there is no fixed poll delay; if it is
# missing or exits we fall back to interval polling so syncing still works.
#
# It also lifts Silent Mode's hard mute on the first volume-up. Silent Mode mutes
# the speaker amp (/sys/class/speaker/mute) and that mute is otherwise only
# cleared by flipping the switch back. So raising the volume bumped ALSA and the
# OSD but produced no sound. When a non-zero volume arrives while the amp is
# muted we clear the mute (and its marker) so volume-up restores audio without
# touching the switch.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SET_VOLUME_DIR=/tmp/system
SET_VOLUME_FILE=/tmp/system/set_volume
SPEAKER_MUTE_FILE=/sys/class/speaker/mute
MUTED_MARKER=/tmp/system/muted
INOTIFYWAIT=/mnt/SDCARD/spruce/bin64/inotifywait
POLL_INTERVAL=0.15     # fallback polling cadence when inotifywait is unavailable

mkdir -p "$SET_VOLUME_DIR" 2>/dev/null

last_seen=""

# Lift Silent Mode's amp mute when the volume is raised above 0.
unmute_if_raised() {
    vol="$1"
    [ "$vol" -gt 0 ] 2>/dev/null || return 0
    [ -w "$SPEAKER_MUTE_FILE" ] || return 0
    [ "$(cat "$SPEAKER_MUTE_FILE" 2>/dev/null)" = "1" ] || return 0
    echo 0 > "$SPEAKER_MUTE_FILE"
    rm -f "$MUTED_MARKER"
    log_message "volume_sync_watchdog.sh: volume raised to $vol, cleared Silent Mode mute."
}

read_current() {
    new_vol=$(cat "$SET_VOLUME_FILE" 2>/dev/null)
    case "$new_vol" in
        ''|*[!0-9]*) return 1 ;;   # ignore empty or non-numeric writes
    esac
    echo "$new_vol"
}

# Mirror one observed value into the bar (SYSTEM_JSON), in place, and handle the
# Silent Mode unmute. Cheap enough to run on every key event, even held.
sync_value() {
    new_vol="$1"
    [ "$new_vol" = "$last_seen" ] && return 0
    last_seen="$new_vol"
    if [ "$new_vol" != "$(get_volume_level)" ]; then
        sed -i "s/\"vol\":[[:space:]]*[0-9]*/\"vol\": $new_vol/" "$SYSTEM_JSON" 2>/dev/null
    fi
    unmute_if_raised "$new_vol"
}

run_event_driven() {
    # -m: stream events; watch the dir (catches in-place echo and atomic mv of
    # the file). Filter to our filename below. Each event triggers a read of the
    # current value, so a burst of writes coalesces to the latest level.
    "$INOTIFYWAIT" -m -q -e modify -e close_write -e moved_to \
        --format '%f' "$SET_VOLUME_DIR" 2>/dev/null | \
    while read -r fname; do
        [ "$fname" = "set_volume" ] || continue
        cur="$(read_current)" || continue
        sync_value "$cur"
    done
}

run_polling_fallback() {
    log_message "volume_sync_watchdog.sh: inotifywait unavailable, using polling fallback."
    while true; do
        if [ -f "$SET_VOLUME_FILE" ]; then
            cur="$(read_current)" && sync_value "$cur"
        fi
        sleep "$POLL_INTERVAL"
    done
}

log_message "volume_sync_watchdog.sh: Started up."

if [ -x "$INOTIFYWAIT" ]; then
    # If inotifywait ever exits, drop back to polling so syncing never stops.
    run_event_driven
    log_message "volume_sync_watchdog.sh: event loop ended, falling back to polling."
fi
run_polling_fallback
