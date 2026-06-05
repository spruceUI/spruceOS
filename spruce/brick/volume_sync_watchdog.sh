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

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SET_VOLUME_FILE=/tmp/system/set_volume
POLL_INTERVAL=0.15

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
                    last="$new_vol"
                fi
                ;;
        esac
    fi
    sleep "$POLL_INTERVAL"
done
