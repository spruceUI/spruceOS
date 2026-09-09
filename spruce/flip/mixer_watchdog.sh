#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

JACK_PATH=/sys/class/gpio/gpio150/value

# Listen before every apply, the first one included. gpiowait exits on the
# next edge of the jack GPIO, so a watcher armed BEFORE the handling catches
# an edge that lands while the codec is being written (or while the handler
# waits for sleep_helper to let go), and the boot-time apply below reads the
# jack with the watcher already up. Handling an edge that turns out to change
# nothing costs one no-op gain write (Flip.sh flip_apply_route_and_gain).
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
    # Re-applies the stored level and route once sleep_helper (if active)
    # has let go of the volume (Flip.sh reapply_volume_on_jack_edge).
    reapply_volume_on_jack_edge
done
