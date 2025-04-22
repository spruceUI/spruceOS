#!/bin/sh

# Didn't wanna import the ENTIRE helperFunctions for one lousy function
log_file="/mnt/SDCARD/Saves/spruce/spruce.log"
log_message() {
    local message="$1"
    local verbose_flag="$2"
    local custom_log_file="${3:-$log_file}"

    # Check if it's a verbose message and if verbose logging is not enabled
    [ "$verbose_flag" = "-v" ] && ! flag_check "log_verbose" && return

    # Handle custom log file
    if [ "$custom_log_file" != "$log_file" ]; then
        mkdir -p "$(dirname "$custom_log_file")"
        touch "$custom_log_file"
    fi

    printf '%s%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${verbose_flag:+ -v}" "$message" | tee -a "$custom_log_file"
}

log_message "*** lid_watchdog.sh: helperFunctions imported." -v

GPIO_PATH="/sys/devices/platform/hall-mh248/hallvalue"

while true; do
    VALUE=$(cat "$GPIO_PATH")
    if [ "$VALUE" -eq 0 ]; then
        log_message "*** lid_watchdog.sh: lid closed - entering S3 sleep" -v
        echo deep > /sys/power/mem_sleep
        echo mem > /sys/power/state
    fi
    sleep 1.5
done

