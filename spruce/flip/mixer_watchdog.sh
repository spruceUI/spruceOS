#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

JACK_PATH=/sys/class/gpio/gpio150/value

# Arm the watcher before every apply, the first one included: an edge during
# the handling is caught by the watcher that is already up.
/mnt/SDCARD/spruce/bin64/gpiowait $JACK_PATH &
PID_GPIO=$!
set_volume "$(( $(get_volume_level) ))"

while true; do
    wait $PID_GPIO

    log_message "*** mixer watchdog: change detected" -v

    # Re-arm first, then handle; never spin if the GPIO went away.
    [ -e "$JACK_PATH" ] || sleep 1
    /mnt/SDCARD/spruce/bin64/gpiowait $JACK_PATH &
    PID_GPIO=$!
    # Flip.sh reapply_volume_on_jack_edge: applies once sleep_helper (if active) lets go.
    reapply_volume_on_jack_edge
done
