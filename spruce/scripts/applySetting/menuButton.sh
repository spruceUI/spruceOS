#!/bin/sh
# Apply Settings -> Button Settings -> Menu button. RGB30 only - it is the only
# device whose menu button is a user choice, because it has no dedicated one and
# has to spend a stick click on it.
#
# RGB30.cfg turns the setting into B_MENU/B_L3/B_R3, but homebutton_watchdog.sh
# reads B_MENU once: it sources the .cfg at startup and then sits in a getevent
# loop for the rest of the session. So changing the setting reached PyUI right
# away - it resolves the click per press - while the in-game menu button stayed
# on whatever was set at boot. Restart the watchdog so it re-sources the .cfg.
#
# Run as the setting's changeCmd. PyUI appends the newly-selected value as $1;
# this only logs it, since the .cfg reads the file itself.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_message "menuButton.sh: menu button is now ${1:-unset}, restarting homebutton_watchdog.sh"

# Backgrounded as a whole: PyUI runs changeCmd synchronously on the UI thread,
# so anything slow here shows up as the settings menu locking up. stdio goes to
# /dev/null so the restarted watchdog does not inherit and hold open whatever
# pipe the caller had - PyUI's, or an ssh session's when testing by hand.
(
    WATCHDOG="/mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh"

    # Shared with the boot launcher (utils/watchdog_launcher.sh, reachable here
    # because helperFunctions.sh sources the platform's device_functions file).
    # It kills the watchdog and the getevent it owns.
    stop_running_watchdog "$WATCHDOG"

    sleep 1

    "$WATCHDOG" &

    # Same pin the boot launcher applies, so the restarted watchdog does not
    # drift onto a different core than it had.
    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}
    pin_cpu "$SYSTEM_CPU" -n homebutton_watchdog.sh &
) </dev/null >/dev/null 2>&1 &
