#!/bin/sh

# idlemon has no deadzone: it treats any byte read from its -e event device as
# "user activity", full stop. That's fine on platforms whose event node only
# carries digital buttons, but on a combined node that also carries raw ADC
# stick/trigger output (see needs_idlemon_activity_filter) it also picks up
# stick jitter, and - on the Smart Pro S at least - RetroArch's own rumble
# driver periodically writing EV_FF (force-feedback) commands to that same
# shared node. Either alone is enough traffic to keep idlemon from ever
# seeing "idle", regardless of whether anyone's actually touching the device.
#
# idlemon can't be reset from outside (no signal for it, no IPC) - only
# restarting it reseeds its idle clock, since it stamps last-activity the
# moment it (re)detects its target process running. So instead of feeding it
# the noisy node directly, this filters the same node ourselves and re-runs
# idlemon_mm.sh (which kills and relaunches every configured idlemon
# instance) whenever it sees activity that isn't just noise.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

needs_idlemon_activity_filter || exit 0

if [ ! -c "$EVENT_PATH_READ_INPUTS_SPRUCE" ]; then
    log_message "idlemon_activity_gate: no such device '$EVENT_PATH_READ_INPUTS_SPRUCE', exiting"
    exit 1
fi

STICK_DEADZONE="${IDLEMON_STICK_DEADZONE:-6000}" # out of a +/-32767 axis range
MIN_RESTART_GAP=5 # seconds; avoid thrashing idlemon during continuous play

last_restart=0

getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" | while read -r line; do
    case "$line" in
        *"key 3 0 "*|*"key 3 1 "*|*"key 3 3 "*|*"key 3 4 "*)
            # Left/right stick axes (STICK_*/STICK_*_2): ignore ADC noise near
            # center, only real deflection counts as activity.
            value="${line##* }"
            value="${value#-}"
            case "$value" in
                ''|*[!0-9]*) continue ;;
            esac
            [ "$value" -ge "$STICK_DEADZONE" ] || continue
            ;;
        *"key 1 "*|*"key 3 16 "*|*"key 3 17 "*|*"key 3 2 "*|*"key 3 5 "*)
            # EV_KEY (buttons), d-pad hat, or analog triggers: genuine input.
            ;;
        *)
            # Whitelist, not blacklist: anything not explicitly recognized as
            # input is ignored, notably EV_SYN (type 0) and EV_FF (type 21).
            continue
            ;;
    esac

    now=$(date +%s)
    [ $((now - last_restart)) -ge "$MIN_RESTART_GAP" ] || continue
    last_restart=$now
    log_message "idlemon_activity_gate: resetting idle timer, saw: $line"
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh > /dev/null 2>&1
done
