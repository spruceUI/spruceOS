#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_message "power_button_watchdog_v2.sh: Started up."

LAST_POWER_DOWN=0
power_hold_pid=""
getevent_pid=""
POWER_EVENT_PIPE="/tmp/power_button_watchdog.$$"

cleanup_power_watchdog () {
    if [ -n "$power_hold_pid" ]; then
        kill "$power_hold_pid" 2>/dev/null
        wait "$power_hold_pid" 2>/dev/null
        power_hold_pid=""
    fi

    if [ -n "$getevent_pid" ]; then
        kill "$getevent_pid" 2>/dev/null
        wait "$getevent_pid" 2>/dev/null
        getevent_pid=""
    fi

    rm -f /tmp/powerbtn /tmp/powerbtn_cancelled "$POWER_EVENT_PIPE"
}

trap 'cleanup_power_watchdog; rm -f /tmp/powerbtn /tmp/powerbtn_cancelled' EXIT
trap 'cleanup_power_watchdog; rm -f /tmp/powerbtn /tmp/powerbtn_cancelled; exit 0' INT TERM

power_key_up () {
    if [ -e /tmp/powerbtn ]; then
        log_message "Power button released at $(date +%s)"  
        rm -f /tmp/powerbtn

        was_cancelled=false
        if [ -e /tmp/powerbtn_cancelled ]; then
            was_cancelled=true
            rm -f /tmp/powerbtn_cancelled
        fi

        # Kill background hold timer if still running
        if [ -n "$power_hold_pid" ]; then
            kill "$power_hold_pid" 2>/dev/null
            wait "$power_hold_pid" 2>/dev/null
            power_hold_pid=""
        fi

        if [ "$was_cancelled" = false ]; then
            /mnt/SDCARD/spruce/scripts/sleep_helper.sh
        fi
    else
        log_message "Power button released during cooldown at $(date +%s)"  
    fi

}

power_key_down () {

    if [ ! -e /tmp/powerbtn ]; then
        power_btn_press_time=$(date +%s)
        log_message "Power button pressed at $power_btn_press_time" 
        touch /tmp/powerbtn

        # Launch background timer that waits required seconds, then triggers the action
        (
            power_hold_time=2
            sleep "$power_hold_time"
            # Check if the powerbtn file still exists (i.e. button still held) AND NOT cancelled (i.e. no other button pressed)
            if [ -e /tmp/powerbtn ] && [ ! -e /tmp/powerbtn_cancelled ]; then
                log_message "power_button_watchdog_v2.sh: Powering off due to power button hold."
                vibrate &
                rm -f /tmp/powerbtn
                rm -f /tmp/powerbtn_cancelled
                if [ -n "$getevent_pid" ]; then
                    kill "$getevent_pid" 2>/dev/null
                fi
                sleep 0.1
                "$POWER_OFF_SCRIPT"
            fi
        ) &
        power_hold_pid=$!
    else
        log_message "Power button pressed during cooldown at $power_btn_press_time"  
    fi
}

while true; do
    log_message "power_button_watchdog_v2.sh: Monitoring power button events on $EVENT_PATH_POWER"
    rm -f "$POWER_EVENT_PIPE"
    if ! mkfifo "$POWER_EVENT_PIPE"; then
        log_message "power_button_watchdog_v2.sh: Failed to create $POWER_EVENT_PIPE"
        sleep 1
        continue
    fi

    getevent -exclusive -pid $$ "$EVENT_PATH_POWER" > "$POWER_EVENT_PIPE" &
    getevent_pid=$!

    while read -r line; do
        now=$(date +%s)
        case $line in
            # Power key down
            *"key $B_POWER 1"*)
                log_message "power_button_watchdog_v2.sh: power_key_down"
                if [ $((now - LAST_POWER_DOWN)) -ge 1 ]; then
                    power_key_down
                    LAST_POWER_DOWN=$(date +%s)
                else
                    log_message "Power button pressed during cooldown at $now, LAST_POWER_DOWN=$LAST_POWER_DOWN"  
                fi
                ;;

            # Power key up
            *"key $B_POWER 0"*)
                    log_message "power_button_watchdog_v2.sh: power_key_up"
                    power_key_up
                    LAST_POWER_DOWN=$(date +%s)
                ;;
            esac
    done < "$POWER_EVENT_PIPE"

    kill "$getevent_pid" 2>/dev/null
    wait "$getevent_pid" 2>/dev/null
    getevent_pid=""
    rm -f "$POWER_EVENT_PIPE"
    log_message "power_button_watchdog_v2.sh: getevent pipe exited, restarting..."
    sleep 1
done
