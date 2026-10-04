#!/bin/sh
# Button Settings > Volume buttons (RGB30). RGB30.cfg turns the choice into
# B_VOLUP/B_VOLDOWN; buttons_watchdog.sh sources the .cfg once at startup, so
# restart it. Backgrounded and detached for the same reasons as menuButton.sh.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_message "volumeButtons.sh: volume buttons are now ${1:-unset}, restarting buttons_watchdog.sh"

(
    WATCHDOG="/mnt/SDCARD/spruce/scripts/buttons_watchdog.sh"
    stop_running_watchdog "$WATCHDOG"
    sleep 1
    "$WATCHDOG" &
    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}
    pin_cpu "$SYSTEM_CPU" -n buttons_watchdog.sh &
) </dev/null >/dev/null 2>&1 &
