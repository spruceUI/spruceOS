#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ -e /tmp/sleep_helper_started ]; then
    log_message "Sleep helper already active, skipping. /tmp/sleep_helper_started exists"
    exit 0 
fi

log_message "Sleep helper starting up..."
rm -f /tmp/power_pressed_flag

touch /tmp/sleep_helper_started
START_TIME=$(date +%s)
getevent | while read -r line; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    # Ignore events for the first 2 seconds of script starting
    # as sometimes the power button can trigger a couple times immediately
    if [ "$ELAPSED" -lt 2 ]; then
        continue
    fi
    case "$line" in
        *"key $B_POWER 1"*) 
            touch /tmp/power_pressed_flag
        ;;
    esac
done &
GET_EVENT_PID=$!


power_button_pressed() {
    if [ -e /tmp/power_pressed_flag ]; then
        rm -f /tmp/power_pressed_flag
        return 0
    else
        return 1
    fi
}

# Clean up on exit
trap 'kill $GET_EVENT_PID 2>/dev/null; rm -f "$POWER_BUTTON_PIPE"' EXIT

get_shutdown_timer() {
    local LID_TIMER
    LID_TIMER="$(get_config_value '.menuOptions."Battery Settings".shutdownFromSleep.selected' "15m")"
    local IDLE_TIMEOUT=0

    case "$LID_TIMER" in
        "Off")  IDLE_TIMEOUT=0 ;;
        "5s")   IDLE_TIMEOUT=5 ;;
        "30s")  IDLE_TIMEOUT=30 ;;
        "1m")   IDLE_TIMEOUT=60 ;;
        "5m")   IDLE_TIMEOUT=300 ;;
        "15m")  IDLE_TIMEOUT=900 ;;
        "30m")  IDLE_TIMEOUT=1800 ;;
        "1h")   IDLE_TIMEOUT=3600 ;;
    esac

    echo "$IDLE_TIMEOUT"
}


trigger_sleep() {
    log_message "Entering pseudosleep"
    device_enter_pseudo_sleep
    lid_ever_closed=false
    pseudo_sleep_exited=false
    # Get the lid powerdown timeout
    local IDLE_TIMEOUT
    IDLE_TIMEOUT=$(get_shutdown_timer)

    if [ "$IDLE_TIMEOUT" -gt 0 ]; then
        log_message "Starting idle timeout countdown: ${IDLE_TIMEOUT}s until poweroff if lid remains closed"
        local elapsed=0
        local current_lid_state

        while [ "$elapsed" -lt "$IDLE_TIMEOUT" ]; do
            current_lid_state=$(device_lid_open)
            log_message "current_lid_state is $current_lid_state"

            
            # Track if lid was ever closed
            if [ "$current_lid_state" = "0" ]; then
                log_message "Detected lid closed, will now wait for it to open"
                lid_ever_closed=true
            fi

            # If lid opened, restore screen and break
            if [ "$current_lid_state" = "1" ] && [ "$lid_ever_closed" = true ]; then
                log_message "Lid opened"
                device_exit_pseudo_sleep
                pseudo_sleep_exited=true 
                break
            elif power_button_pressed; then
                log_message "Power button pressed, exiting pseudosleep"
                device_exit_pseudo_sleep
                pseudo_sleep_exited=true 
                break
            fi

            sleep 1
            elapsed=$((elapsed + 1))
        done

        # Timeout reached without exitting sleep → poweroff
        if [ "$pseudo_sleep_exited" = false ]; then
            log_message "Lid closed for ${IDLE_TIMEOUT}s, triggering poweroff"
            device_exit_pseudo_sleep
            sleep 0.1
            "$POWER_OFF_SCRIPT" &
        fi
    else
        # Lid closed but no poweroff timer — just stay in pseudosleep
        while true; do
            # Track if lid was ever closed
            if [ "$current_lid_state" = "0" ]; then
                lid_ever_closed=true
            fi

            current_lid_state=$(device_lid_open)
            # If lid opened, restore screen and break
            if [ "$current_lid_state" = "1" ] && [ "$lid_ever_closed" = true ]; then
                log_message "Lid opened"
                device_exit_pseudo_sleep
                break
            elif power_button_pressed; then
                log_message "Power button pressed, exiting pseudosleep"
                device_exit_pseudo_sleep
                break
            fi
            sleep 1
        done
    fi
}

trigger_sleep

kill "$GET_EVENT_PID" 2>/dev/null

sleep 2 #don't allow resleeping for a few seconds
rm -f /tmp/sleep_helper_started
