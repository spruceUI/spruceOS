#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ -e /tmp/sleep_helper_started ]; then
    log_message "Sleep helper already active, skipping. /tmp/sleep_helper_started exists" -v
    exit 0 
fi

current_app="$(get_current_app)"
log_activity_event "$current_app" "STOP"

log_message "Sleep helper starting up..."
rm -f /tmp/power_pressed_flag

touch /tmp/sleep_helper_started
START_TIME=$(date +%s)
getevent $EVENT_PATH_POWER | while read -r line; do
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
        "Off")   IDLE_TIMEOUT=2592000  ;; # 30 days
        "5s")    IDLE_TIMEOUT=5 ;;
        "30s")   IDLE_TIMEOUT=30 ;;
        "1m")    IDLE_TIMEOUT=60 ;;
        "2m")    IDLE_TIMEOUT=120 ;;
        "5m")    IDLE_TIMEOUT=300 ;;
        "10m")   IDLE_TIMEOUT=600 ;;
        "15m")   IDLE_TIMEOUT=900 ;;
        "30m")   IDLE_TIMEOUT=1800 ;;
        "60m")   IDLE_TIMEOUT=3600 ;;
        "2h")    IDLE_TIMEOUT=7200 ;;
        "3h")    IDLE_TIMEOUT=10800 ;;
        "4h")    IDLE_TIMEOUT=14400 ;;
        "6h")    IDLE_TIMEOUT=21600 ;;
        "12h")   IDLE_TIMEOUT=43200 ;;
        "24h")   IDLE_TIMEOUT=86400 ;;
        *)       IDLE_TIMEOUT=900 ;;
    esac

    echo "$IDLE_TIMEOUT"
}


read_system_json_int() {
    key="$1"

    if [ -z "${SYSTEM_JSON:-}" ] || [ ! -f "$SYSTEM_JSON" ]; then
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        return 1
    fi

    value="$(jq -r "$key // empty" "$SYSTEM_JSON" 2>/dev/null || true)"
    case "$value" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    printf '%s\n' "$value"
    return 0
}

run_timeout_poweroff() {
    "$POWER_OFF_SCRIPT"
    poweroff_status=$?
    if [ "$poweroff_status" -eq 0 ]; then
        rm -f /tmp/sleep_helper_started
        exit 0
    fi

    log_message "Timeout poweroff failed with status $poweroff_status; resuming wake path"
    return "$poweroff_status"
}

trigger_sleep() {
    log_message "Entering sleep"
    lid_ever_closed=false
    sleep_exited=false
    # Get the lid powerdown timeout
    local IDLE_TIMEOUT
    IDLE_TIMEOUT=$(get_shutdown_timer)
    start_ts=$(date +%s)
    set_volume 0 false # Mute on sleep so when we wake to shutdown it's silent
    device_enter_sleep "$IDLE_TIMEOUT"
    if [ "$(device_uses_pseudo_sleep)" = "true" ]; then
        log_message "Device uses pseudosleep -- starting idle loop"
        log_message "Starting idle timeout countdown: ${IDLE_TIMEOUT}s until poweroff if lid remains closed"
        local elapsed=0
        local current_lid_state

        while [ "$elapsed" -lt "$IDLE_TIMEOUT" ]; do
            current_lid_state=$(device_lid_open)
                
            # Track if lid was ever closed
            if [ "$current_lid_state" = "0" ]; then
                log_message "Detected lid closed, will now wait for it to open"
                lid_ever_closed=true
            fi

            # If lid opened, restore screen and break
            if [ "$current_lid_state" = "1" ] && [ "$lid_ever_closed" = true ]; then
                log_message "Lid opened"
                sleep_exited=true 
                break
            elif power_button_pressed; then
                if [ "$current_lid_state" = "1" ]; then
                    log_message "Power button pressed, exiting pseudosleep"
                    sleep_exited=true 
                    break
                else
                    log_message "Power button pressed but lid is closed, continuing pseudosleep"
                fi
            fi

            sleep 1
            now_ts=$(date +%s)
            elapsed=$((now_ts - start_ts))
            if [ "$elapsed" -ge "$IDLE_TIMEOUT" ]; then
                local DISABLE_IF_CHARGING="$(get_config_value '.menuOptions."Battery Settings".disableShutdownFromSleepIfCharging.selected' "False")"
                if [ "$DISABLE_IF_CHARGING" = "True" ] && [ "$(device_get_charging_status)" = "Charging" ]; then
                    log_message "Device is plugged in and shutdown prevention option enabled, restarting sleep countdown"
                    start_ts=$(date +%s)
                    elapsed=$((now_ts - start_ts))
                fi
            fi
        done

        # Timeout reached without exitting sleep → poweroff
        if [ "$sleep_exited" = false ]; then
            log_message "Lid closed for ${IDLE_TIMEOUT}s, triggering poweroff"
            # Set clocks bad to full speed
            set_performance
            sleep 0.1
            run_timeout_poweroff
        fi
    else
        
        while [ "$(device_lid_open)" = "0" ]; do
            if [ "$(device_woke_via_timer)" = "true" ]; then
                break
            fi

            log_message "Lid is closed, but not in sleep -- Retrigger sleep -- IDLE_TIMEOUT=$IDLE_TIMEOUT"
            device_continue_sleep
        done


        if [ "$(device_woke_via_timer)" = "true" ]; then
            log_message "Idle time exceeded, triggering poweroff -- IDLE_TIMEOUT=$IDLE_TIMEOUT"
            sleep 0.1
            run_timeout_poweroff
        else
            log_message "Woke from sleep manually"
        fi
    fi
}

# Disable idle/shutdown timer during sleep
killall -q idlemon 2>/dev/null
killall -q idlemon_mm.sh 2>/dev/null

trigger_sleep

device_exit_sleep

log_activity_event "$current_app" "START"

# Restore volume before unpausing so audio is ready
VOLUME_LV="$(read_system_json_int '.vol' || true)"
case "$VOLUME_LV" in
    ''|*[!0-9]*) ;;
    *) set_volume "$VOLUME_LV" ;;
esac


kill "$GET_EVENT_PID" 2>/dev/null

sleep 2 #don't allow resleeping for a few seconds
rm -f /tmp/sleep_helper_started

# Restart idle timer if needed (idlemon_mm checks for it)
/mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh &
