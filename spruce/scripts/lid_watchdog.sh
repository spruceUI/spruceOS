#!/bin/sh

. /mnt/SDCARD/spruce/scripts/audioFunctions.sh

FLAGS_DIR="/mnt/SDCARD/spruce/flags"

# Check if a flag exists
# Usage: flag_check "flag_name"
# Returns 0 if the flag exists (with or without .lock extension), 1 if it doesn't
flag_check() {
    local flag_name="$1"
    if [ -f "$FLAGS_DIR/${flag_name}" ] || [ -f "$FLAGS_DIR/${flag_name}.lock" ]; then
        return 0
    else
        return 1
    fi
}

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

# default to open
current_value=1
while true; do
    VALUE=$(cat "$GPIO_PATH")
    if [ "$VALUE" -eq 0 ] && [ "$current_value" -eq 1 ]; then
        log_message "*** lid_watchdog.sh: lid closed - entering S3 sleep" -v
        current_value=0

        echo deep > /sys/power/mem_sleep
        echo mem > /sys/power/state
    elif [ "$VALUE" -eq 1 ] && [ "$current_value" -eq 0 ]; then
        current_value=1
        log_message "*** lid_watchdog.sh: lid opened" -v

        reset_playback_pack
    fi

    /mnt/SDCARD/spruce/bin64/inotifywait "$GPIO_PATH" -e modify -t 1 >/dev/null 2>&1
done

