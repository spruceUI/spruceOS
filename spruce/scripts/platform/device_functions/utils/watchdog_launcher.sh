#!/bin/sh

# Stop an already-running instance of a watchdog, plus the getevent it owns.
#
# The launchers below run once per start of the frontend, NOT once per boot. If
# spruce restarts without a reboot - systemd's Restart=on-failure, or a
# "systemctl restart" while debugging - the previous run's watchdogs are still
# alive, and starting a second set means every button press gets handled twice.
# Nothing else reaps them: on dArkMoss the unit is deliberately KillMode=process,
# because spruce's own children have to outlive the frontend during its shutdown
# sequence, so systemd only ever signals the main process.
#
# Matched on the full script path. pin_cpu carries the bare basename in its argv,
# so matching that instead would kill the pins rather than the watchdogs.
stop_running_watchdog() {
    _swd_script="$1"
    for _swd_pid in $(pgrep -f "$_swd_script" 2>/dev/null); do
        [ "$_swd_pid" = "$$" ] && continue
        # getevent is spawned with -pid of its watchdog and is meant to exit with
        # it, but it only notices when it next tries to write - with no button
        # pressed it outlives its reader indefinitely. Take it by that pid; a
        # bare "killall getevent" would hit the other watchdogs' readers too.
        for _swd_ge in $(pgrep -f "getevent.*-pid $_swd_pid" 2>/dev/null); do
            kill "$_swd_ge" 2>/dev/null
        done
        kill "$_swd_pid" 2>/dev/null
    done
    unset _swd_script _swd_pid _swd_ge
}

launch_common_startup_watchdogs_v2() {
    log_message "Launching common startup watchdogs"
    HAS_LID="${1:-false}" 

    # Clear out anything a previous run of the frontend left behind. The lid one
    # is in the list unconditionally: if the last run started it and this one has
    # no lid, it still has to go.
    for _wd in \
        /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh \
        /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh \
        /mnt/SDCARD/spruce/scripts/low_power_warning.sh \
        /mnt/SDCARD/spruce/scripts/power_button_watchdog_v2.sh \
        /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh \
        /mnt/SDCARD/spruce/scripts/lid_watchdog_v2.sh
    do
        stop_running_watchdog "$_wd"
    done
    unset _wd

    /mnt/SDCARD/spruce/scripts/homebutton_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
    /mnt/SDCARD/spruce/scripts/low_power_warning.sh &
    /mnt/SDCARD/spruce/scripts/power_button_watchdog_v2.sh &
    /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh &

    SYSTEM_CPU=${DEVICE_MAX_CORES_ONLINE%"${DEVICE_MAX_CORES_ONLINE#?}"}
    pin_cpu "$SYSTEM_CPU" -n homebutton_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n idlemon_mm.sh &
    pin_cpu "$SYSTEM_CPU" -n low_power_warning.sh &
    pin_cpu "$SYSTEM_CPU" -n power_button_watchdog_v2.sh &
    pin_cpu "$SYSTEM_CPU" -n buttons_watchdog.sh &

    if [ "$HAS_LID" = "true" ]; then
        /mnt/SDCARD/spruce/scripts/lid_watchdog_v2.sh &
        pin_cpu "$SYSTEM_CPU" -n lid_watchdog_v2.sh &
    fi


}