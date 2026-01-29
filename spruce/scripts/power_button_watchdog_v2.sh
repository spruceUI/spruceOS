#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_message "power_button_watchdog_v2.sh: Started up."



power_key_up () {
    log_message "Power button released at $(date +%s)"  
    if [ -e /tmp/powerbtn ]; then
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
            /mnt/SDCARD/spruce/scripts/sleep_helper.sh &
        fi
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
                killall getevent 2>/dev/null
                sleep 0.1
                "$POWER_OFF_SCRIPT"
            fi
        ) &
        power_hold_pid=$!
    fi
}

LAST_POWER_DOWN=0
log_message "power_button_watchdog_v2.sh: Monitoring power button events on $EVENT_PATH_POWER"
getevent -pid $$ $EVENT_PATH_POWER | while read line; do
    if [ -e /tmp/sleep_helper_started ]; then
        log_message "power_button_watchdog_v2.sh: Sleep helper active, skipping power button event."
        continue
    fi

    now=$(date +%s)
    case $line in
        # Power key down
        *"key $B_POWER 1"*)
            if [ $((now - LAST_POWER_DOWN)) -ge 1 ]; then
                log_message "power_button_watchdog_v2.sh: power_key_down"
                power_key_down
                LAST_POWER_DOWN=$now
            fi
            ;;

        # Power key up
        *"key $B_POWER 0"*)
                log_message "power_button_watchdog_v2.sh: power_key_up"
                power_key_up
            ;;
        esac
done

