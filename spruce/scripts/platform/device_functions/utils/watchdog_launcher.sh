#!/bin/sh

# True only if pid $1 is actually RUNNING script $2 - the script is argv[0] or
# argv[1] - rather than merely mentioning it somewhere in its command line.
# "pgrep -f <path>" alone is too loose: anything carrying the path further along
# its arguments matches, and this function kills what it matches.
_wd_runs_script() {
    _wd_a0=""
    _wd_a1=""
    _wd_n=0
    for _wd_w in $(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null); do
        _wd_n=$((_wd_n + 1))
        [ "$_wd_n" -eq 1 ] && _wd_a0="$_wd_w"
        [ "$_wd_n" -eq 2 ] && _wd_a1="$_wd_w"
        [ "$_wd_n" -ge 2 ] && break
    done
    [ "$_wd_a0" = "$2" ] || [ "$_wd_a1" = "$2" ]
}

# Print the pids of pid $1's getevent children.
#
# By parentage, not by command line. buttons_watchdog's getevent is spawned with
# no -pid argument, so a "getevent .* -pid N" match misses it entirely and it
# leaks one orphan per restart - measured on a Brick Pro, ppid 1, still holding
# the input node. Every watchdog's getevent is a direct child, so this catches
# both shapes.
_wd_getevent_children() {
    for _wd_d in /proc/[0-9]*; do
        [ -r "$_wd_d/stat" ] || continue
        read -r _wd_x _wd_comm _wd_st _wd_ppid _wd_rest < "$_wd_d/stat" 2>/dev/null || continue
        [ "$_wd_comm" = "(getevent)" ] && [ "$_wd_ppid" = "$1" ] && echo "${_wd_d#/proc/}"
    done
}

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
#
# At a cold boot nothing matches, so the whole thing - including the /proc walk
# in _wd_getevent_children - never runs.
stop_running_watchdog() {
    _swd_script="$1"
    for _swd_pid in $(pgrep -f "$_swd_script" 2>/dev/null); do
        [ "$_swd_pid" = "$$" ] && continue
        _wd_runs_script "$_swd_pid" "$_swd_script" || continue
        # getevent first: killing the watchdog on its own orphans its reader,
        # which then holds the input node until it next tries to write.
        for _swd_ge in $(_wd_getevent_children "$_swd_pid"); do
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