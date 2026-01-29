
SLEEP_TIMER_FILE="/tmp/sleep_timer_info"

get_hw_epoch() {
    # hwclock output like: Sat Jan 10 14:23:54 2026  0.000000 seconds
    hw_output=$(hwclock 2>/dev/null)
    set -- $hw_output
    MON=$2
    DAY=$3
    TIME=$4
    YEAR=$5
    
    # Convert month name to number
    case "$MON" in
        Jan) MM=01 ;;
        Feb) MM=02 ;;
        Mar) MM=03 ;;
        Apr) MM=04 ;;
        May) MM=05 ;;
        Jun) MM=06 ;;
        Jul) MM=07 ;;
        Aug) MM=08 ;;
        Sep) MM=09 ;;
        Oct) MM=10 ;;
        Nov) MM=11 ;;
        Dec) MM=12 ;;
        *) MM=00 ;;  # fallback
    esac

    HW_STR="${YEAR}-${MM}-${DAY} ${TIME}"

    # Convert to epoch seconds
    date -d "$HW_STR" +%s 2>/dev/null
}

# -----------------------------
# Save sleep timing info
# -----------------------------
save_sleep_info() {
    IDLE_TIMEOUT="$1"

    START_EPOCH="$(get_hw_epoch)"
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

    NOW_EPOCH="$(get_hw_epoch)"
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

    NOW_EPOCH="$(get_hw_epoch)"
    [ -z "$NOW_EPOCH" ] && return 1

    REMAINING=$(( TARGET_EPOCH - NOW_EPOCH ))
    # Clamp to at least 1 second if positive
    [ "$REMAINING" -gt 0 ] && [ "$REMAINING" -lt 1 ] && REMAINING=1

    echo "$REMAINING"
    return 0
}

device_continue_sleep() {
    log_message "device_continue_sleep: Checking remaining sleep time"

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
    set_wake_alarm "$REMAINING" || return 1

    # Go back to sleep
    trigger_device_sleep
}