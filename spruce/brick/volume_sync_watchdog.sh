#!/bin/sh
# Mirror the firmware volume value into spruce's stored volume so the in-UI
# volume bar tracks the hardware Volume +/- keys, including while held.
#
# On the Brick the physical volume keys are handled by the stock firmware
# (trimui_inputd/keymon), which adjusts ALSA and writes the new level to
# /tmp/system/set_volume on every key event (autorepeat included). spruce never
# read that file back, so its own .vol (SYSTEM_JSON) only changed when spruce
# itself set the volume. The UI volume bar reads .vol, so holding a volume key
# moved the audio but not the bar (it updated once at most, never ramped).
#
# This watchdog polls /tmp/system/set_volume and, on each change, pushes the
# value through spruce's set_volume so .vol stays in sync and the bar redraws.
# set_volume is called config-only with the OSD suppressed: the firmware already
# draws its own volume OSD for the hardware keys, and set_volume is a no-op when
# the value is unchanged, so re-syncing the same number is harmless.
#
# It also lifts Silent Mode's hard mute on the first volume-up. Silent Mode mutes
# the speaker amp (/sys/class/speaker/mute) and that mute is otherwise only
# cleared by flipping the switch back. So raising the volume bumped ALSA and the
# OSD but produced no sound. When a non-zero volume arrives while the amp is
# muted we clear the mute (and its marker) so volume-up restores audio without
# touching the switch.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SET_VOLUME_FILE=/tmp/system/set_volume
SPEAKER_MUTE_FILE=/sys/class/speaker/mute
MUTED_MARKER=/tmp/system/muted
POLL_INTERVAL=0.15

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

log_message "volume_sync_watchdog.sh: Started up."

last=""
while true; do
    if [ -f "$SET_VOLUME_FILE" ]; then
        new_vol=$(cat "$SET_VOLUME_FILE" 2>/dev/null)
        case "$new_vol" in
            ''|*[!0-9]*) ;; # ignore empty or non-numeric writes
            *)
                if [ "$new_vol" != "$last" ]; then
                    if [ "$new_vol" != "$(get_volume_level)" ]; then
                        # config-only, suppress spruce OSD (firmware shows its own)
                        set_volume "$new_vol" true false
                    fi
                    # A volume-up while Silent Mode muted the amp should bring
                    # sound back without flipping the switch.
                    unmute_if_raised "$new_vol"
                    last="$new_vol"
                fi
                ;;
        esac
    fi
    sleep "$POLL_INTERVAL"
done
