# This is a collection of functions that are used in multiple scripts
# Please do not add any dependencies here, this file is meant to be self-contained
# Keep methods in alphabetical order

# Gain access to the global variables by adding this to the top of your script:
# . "$GLOBAL_FUNCTIONS"
# This is defined in the runtime.sh file
# or calling the file directly like:
# . /mnt/SDCARD/.tmp_update/scripts/globalFunctions.sh

# Call this like:
# log_message "Your message here"
# To output to a custom log file, set the variable within your script:
# log_file="/mnt/SDCARD/App/MyApp/spruce.log"
# This will log the message to the spruce.log file in the Saves/spruce folder
log_file="/mnt/SDCARD/Saves/spruce/spruce.log"
max_size=$((10 * 1024 * 1024))  # 10MB in bytes
lines_to_keep=30

log_message() {
    local message="$1"
    local custom_log_file="${2:-$log_file}"

    # Ensure the directory for the log file exists
    mkdir -p "$(dirname "$custom_log_file")"

    # Check if custom log file exists, if not, use default log file
    if [ ! -f "$custom_log_file" ]; then
        mkdir -p "$(dirname "$log_file")"
        custom_log_file="$log_file"
    fi

    # Ensure the log file exists
    touch "$custom_log_file"

    # Check if file exists and is larger than max_size
    if [ -f "$custom_log_file" ] && [ $(stat -c%s "$custom_log_file") -gt $max_size ]; then
        # Keep last 30 lines and save to a temp file
        tail -n $lines_to_keep "$custom_log_file" > "$custom_log_file.tmp"
        # Replace original file with trimmed version
        mv "$custom_log_file.tmp" "$custom_log_file"
        echo "Log file trimmed to last $lines_to_keep lines due to size limit." >> "$custom_log_file"
    fi

    # Append new log message
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$custom_log_file"
    echo "$message"
}

# Call with 
# show_image "Image Path" 5
# This will show the image at the given path and kill any existing show processes
# If display_time is provided, it will sleep for that many seconds and then kill the show process
show_image() {
    local image=$1
    local display_time=$2

    if [ ! -f "$image" ]; then
        log_message "Image file not found at $image"
        return 1
    fi

    killall -9 show
    show "$image" &
    local show_pid=$!

    if [ -n "$display_time" ] && [ "$display_time" -eq "$display_time" ] 2>/dev/null; then
        sleep "$display_time"
        kill $show_pid
    fi
}

# Vibrate the device
# Usage: vibrate [duration]
# If no duration is provided, defaults to 100ms
vibrate() {
    local duration=${1:-100}
    echo "$duration" > /sys/devices/virtual/timed_output/vibrator/enable
}
