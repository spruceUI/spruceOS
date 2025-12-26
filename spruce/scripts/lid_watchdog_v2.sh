#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

POWER_OFF_SCRIPT="/mnt/SDCARD/spruce/scripts/save_poweroff.sh"


get_lid_timer() {
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


# Wait until hall sensor is ready
for i in $(seq 1 25); do
    lid_hall_ready && break
    sleep 0.2
done

if ! lid_hall_ready; then
    log_message "Lid sensor never became ready, lid watchdog disabled"
    exit 1
fi

log_message "Lid watchdog started, monitoring lid state"

# Read initial lid state
prev_state=$(device_lid_open)

while true; do
    # Read current lid state (1 = open, 0 = closed)
    current_state=$(device_lid_open)
    
    # Detect lid close event (transition from 1 to 0)
    if [ "$prev_state" = "1" ] && [ "$current_state" = "0" ]; then
        log_message "Lid closed detected - entering pseudosleep"
        enter_pseudo_sleep &

        # Get the lid powerdown timeout
        IDLE_TIMEOUT=$(get_lid_timer)

        # Only start poweroff countdown if timeout is nonzero
        if [ "$IDLE_TIMEOUT" -gt 0 ]; then
            log_message "Starting idle timeout countdown: ${IDLE_TIMEOUT}s until poweroff if lid remains closed"
            elapsed=0
            while [ "$elapsed" -lt "$IDLE_TIMEOUT" ]; do
                current_state=$(device_lid_open)
                
                # If lid opened, restore screen and break out
                if [ "$current_state" = "1" ]; then
                    log_message "Lid opened - exiting pseudosleep"
                    exit_pseudo_sleep
                    break
                fi
                
                sleep 1
                elapsed=$((elapsed + 1))
            done
            
            # If we reached the timeout with lid still closed, poweroff
            current_state=$(device_lid_open)
            if [ "$current_state" = "0" ] && [ "$elapsed" -ge "$IDLE_TIMEOUT" ]; then
                log_message "Lid closed for ${IDLE_TIMEOUT}s, triggering poweroff"
                exit_pseudo_sleep
                sleep 0.1
                "$POWER_OFF_SCRIPT" &
            fi
        else
            # Lid closed but no poweroff timer — just stay in pseudosleep
            while true; do
                current_state=$(device_lid_open)
                if [ "$current_state" = "1" ]; then
                    log_message "Lid opened - exiting pseudosleep"
                    exit_pseudo_sleep
                    break
                fi
                sleep 1
            done
        fi
    fi

    
    prev_state="$current_state"
    sleep 0.5
done
