
SLEEP_TIMER_FILE="/tmp/sleep_timer_info"

# -----------------------------
# Save sleep timing info
# -----------------------------
save_sleep_info() {
    IDLE_TIMEOUT="$1"

    START_EPOCH="$(device_get_hw_epoch)"
    [ -z "$START_EPOCH" ] && {
        log_message "ERROR: Unable to read hwclock"
        return 1
    }

    TARGET_EPOCH=$(( START_EPOCH + IDLE_TIMEOUT ))

    cat >"$SLEEP_TIMER_FILE" <<EOF
START_EPOCH=$START_EPOCH
TIMEOUT=$IDLE_TIMEOUT
TARGET_EPOCH=$TARGET_EPOCH
EOF

    sync
    return 0
}

# -----------------------------
# Program the RTC wakealarm
# -----------------------------
set_wake_alarm() {
    IDLE_TIMEOUT="$1"
    WAKE_ALARM_PATH="$2"

    # If timeout is not positive, do not set an alarm
    if [ "$IDLE_TIMEOUT" -le 0 ]; then
        log_message "set_wake_alarm: IDLE_TIMEOUT <= 0, not setting wakealarm"
        return 0
    fi

    if [ -e "$WAKE_ALARM_PATH" ]; then
        # Clear previous alarm first (important on some BSP kernels)
        echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null

        if ! echo "+$IDLE_TIMEOUT" >"$WAKE_ALARM_PATH" 2>/dev/null; then
            log_message "WARNING: Failed to write WAKE_ALARM_PATH"
            return 1
        fi

        log_message "set_wake_alarm: Wakealarm set for +$IDLE_TIMEOUT seconds"
    else
        log_message "WARNING: WAKE_ALARM_PATH missing, relying on external wake"
    fi

    return 0
}

clear_wake_alarm() {
    WAKE_ALARM_PATH="$1"

    if [ -e "$WAKE_ALARM_PATH" ]; then
        echo 0 > "$WAKE_ALARM_PATH"
        log_message "clear_wake_alarm: Wakealarm cleared"
    fi
}

device_woke_via_timer() {
    [ ! -f "$SLEEP_TIMER_FILE" ] && {
        echo "false"
        return
    }

    . "$SLEEP_TIMER_FILE"

    NOW_EPOCH="$(device_get_hw_epoch)"
    [ -z "$NOW_EPOCH" ] && {
        log_message "ERROR: Unable to read hwclock"
        echo "false"
        return
    }

    # Allow small drift (RTC granularity / resume latency)
    DRIFT_TOLERANCE=10

    if [ "$NOW_EPOCH" -ge $(( TARGET_EPOCH - DRIFT_TOLERANCE )) ]; then
        echo "true"
    else
        echo "false"
    fi
}



# -----------------------------
# Compute remaining time for sleep
# -----------------------------
compute_remaining_sleep_time() {
    # Load saved timing
    [ ! -f "$SLEEP_TIMER_FILE" ] && return 1
    . "$SLEEP_TIMER_FILE"

    NOW_EPOCH="$(device_get_hw_epoch)"
    [ -z "$NOW_EPOCH" ] && return 1

    REMAINING=$(( TARGET_EPOCH - NOW_EPOCH ))
    # Clamp to at least 1 second if positive
    [ "$REMAINING" -gt 0 ] && [ "$REMAINING" -lt 1 ] && REMAINING=1

    echo "$REMAINING"
    return 0
}

# Woken with the lid closed, e.g. by a charger being plugged in: stay up long enough
# for charger detection to finish, or the device suspends again before it charges.
# 0 is no wait; a platform that needs one sets it after sourcing this file.
SLEEP_CHARGER_SETTLE_SECONDS="${SLEEP_CHARGER_SETTLE_SECONDS:-0}"

# 0 once the wait is over with the lid still closed, 1 if the lid opened
wait_for_charger_to_settle() {
    [ "$SLEEP_CHARGER_SETTLE_SECONDS" -gt 0 ] || return 0
    _settle_waited=0
    while [ "$_settle_waited" -lt $((SLEEP_CHARGER_SETTLE_SECONDS * 2)) ]; do
        [ "$(device_lid_open)" = "1" ] && return 1
        sleep 0.5
        _settle_waited=$((_settle_waited + 1))
    done
    log_message "device_continue_sleep: charger status after ${SLEEP_CHARGER_SETTLE_SECONDS}s: $(device_get_charging_status 2>/dev/null)"
    return 0
}

device_continue_sleep() {
    log_message "device_continue_sleep: Checking remaining sleep time"

    # The wait counts against the remaining sleep time, so compute that afterwards
    if ! wait_for_charger_to_settle; then
        log_message "device_continue_sleep: lid opened, not suspending again"
        return 0
    fi

    REMAINING="$(compute_remaining_sleep_time)"
    if [ $? -ne 0 ] || [ -z "$REMAINING" ]; then
        log_message "device_continue_sleep: No valid sleep state or hwclock read failed"
        return 1
    fi

    if [ "$REMAINING" -le 0 ]; then
        log_message "device_continue_sleep: Timer already expired"
        return 0
    fi

    # Re-arm the wakealarm using earlier function
    set_wake_alarm "$REMAINING" "$WAKE_ALARM_PATH" || return 1

    # Go back to sleep
    trigger_device_sleep
}
