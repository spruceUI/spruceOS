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
# To output to a custom log file, use:
# log_message "Your message here" "/path/to/your/custom/logfile.log"
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Custom log file not found. Using default log file." >> "$log_file"
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

# Call with show_image "Image Path"
# This will show the image at the given path and kill any existing show processes
show_image() {
    local image=$1
    if [ ! -f "$image" ]; then
        log_message "Image file not found at $image"
        exit 1
    fi
    killall -9 show
    show "$image" &
}