#!/bin/sh

# Wake on lid open for the BaseOS clamshells (RG SP, RG34XX SP, RG35XX SP).
#
# Only their kernels have os_sleep. BaseOS's rcS writes stock's Super Standby
# value (16) to it at boot: suspend then stops the USB host controllers and
# leaves the hall sensor out of the wake set, so opening the lid does nothing
# and only POWER wakes the device. Writing 0 puts the hall sensor back, at 5-6
# times the battery drain while asleep (BaseOS docs/05-runtime-power-network.md).
# The driver treats any nonzero value as Super Standby and reads back nothing.
#
# The timed options turn lid wake off partway through a sleep, which needs the
# kernel awake: an RTC alarm ends the window, and the device resumes, switches
# and suspends again with the lid still shut. On an RG SP the foreground app ran
# for about 0.2 s of that, less than it already runs between a lid close and the
# first suspend, so it is not paused.
XX_OS_SLEEP="${XX_OS_SLEEP:-/sys/class/power_supply/axp2202-battery/os_sleep}"

xx_lid_wake_supported() {
    [ -w "$XX_OS_SLEEP" ] && has_lid
}

# How far into a sleep opening the lid still wakes the device, in seconds:
# 0 for the whole sleep, -1 never.
xx_lid_wake_window() {
    case "$(get_config_value '.menuOptions."Battery Settings".wakeOnLidOpen.selected' "Off")" in
        "Always") echo 0 ;;
        "10m")    echo 600 ;;
        "30m")    echo 1800 ;;
        *)        echo -1 ;;
    esac
}

# xx_set_lid_wake on|off. A failed write only costs the setting, never the sleep.
xx_set_lid_wake() {
    if [ "$1" = "on" ]; then _xx_policy=0; else _xx_policy=16; fi
    { printf '%s' "$_xx_policy" > "$XX_OS_SLEEP"; } 2>/dev/null ||
        log_message "xx_set_lid_wake: could not write $_xx_policy to $XX_OS_SLEEP"
}

# device_enter_sleep's suspend, called with the shutdown alarm armed. Returns on
# a wake for sleep_helper to judge: the lid, POWER or the shutdown alarm. On
# failure it drops the armed flag, so sleep_helper reads its clock and sleeps
# on to the original shutdown time.
xx_suspend_with_lid_wake() {
    local shutdown_in="$1"
    local window lid_at_start remaining

    if ! xx_lid_wake_supported; then
        trigger_device_sleep
        return
    fi

    window="$(xx_lid_wake_window)"
    # Only an alarm can end a window: without one, keep BaseOS's default.
    if [ "$window" -lt 0 ] || { [ "$window" -gt 0 ] && [ ! -w "$WAKE_ALARM_PATH" ]; }; then
        xx_set_lid_wake off
        trigger_device_sleep
        return
    fi

    xx_set_lid_wake on
    # Always, or a shutdown due before the window ends: one suspend.
    if [ "$window" -eq 0 ] || [ "$window" -ge "$shutdown_in" ]; then
        trigger_device_sleep
        return
    fi

    # The window's alarm replaces the shutdown alarm until the window ends.
    lid_at_start="$(device_lid_open)"
    if ! set_wake_alarm "$window" "$WAKE_ALARM_PATH"; then
        rm -f "$WAKE_ALARM_ARMED_FLAG"
        return 1
    fi
    log_message "Lid wake on for the first ${window}s of sleep"

    while :; do
        # A suspend refused outright (a wakeup already pending) is retried.
        trigger_device_sleep || sleep 1
        # An alarm still pending means the lid or POWER woke us. POWER in a
        # pocket, lid shut, sleeps on with the same alarm.
        [ -n "$(cat "$WAKE_ALARM_PATH" 2>/dev/null)" ] || break
        [ "$(device_lid_open)" = "1" ] && return 0
    done

    # The window's alarm fired; drop the flag so it is not taken for the shutdown.
    rm -f "$WAKE_ALARM_ARMED_FLAG"
    # A lid opened just as the window ended is still the user, unless it has
    # been open since the sleep began (a sleep started with POWER).
    if [ "$lid_at_start" = "0" ] && [ "$(device_lid_open)" = "1" ]; then
        return 0
    fi

    xx_set_lid_wake off
    remaining="$(compute_remaining_sleep_time)" && [ -n "$remaining" ] || return 1
    # Already due: sleep_helper's clock finds the shutdown time reached.
    [ "$remaining" -gt 0 ] || return 0
    set_wake_alarm "$remaining" "$WAKE_ALARM_PATH" || return 1
    touch "$WAKE_ALARM_ARMED_FLAG"
    log_message "Lid wake window over; Super Standby for the ${remaining}s left until shutdown"
    trigger_device_sleep
}
