#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

VOLUME_LV=$(get_volume_level)
set_volume "$(( VOLUME_LV ))"

JACK_PATH=/sys/class/gpio/gpio150/value

while true; do

    /mnt/SDCARD/spruce/bin64/gpiowait $JACK_PATH &
    PID_GPIO=$!
    wait -n

    log_message "*** mixer watchdog: change detected" -v

    kill $PID_GPIO 2>/dev/null
    # Re-applies the stored level and route, unless sleep_helper owns the
    # volume right now (Flip.sh reapply_volume_on_jack_edge).
    reapply_volume_on_jack_edge
done
