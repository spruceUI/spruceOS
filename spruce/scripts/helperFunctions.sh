# Function summaries:

# acknowledge: Waits for user to press A, B, or Start button
# auto_regen_tmp_update: makes .tmp_update/updater if needed
# check_and_connect_wifi: Polls for Wifi, Cancels on Start Press
# cores_online: Sets the number of CPU cores to be online
# display: Displays text on the screen with various options
# flag_check: Checks if a flag exists
# flag_add: Adds a flag
# flag_remove: Removes a flag
# get_button_press: Returns the name of the last button pressed
# log_message: Logs a message to a file
# log_precise: Logs messages with greater precision for performance testing
# log_verbose: Turns on or off verbose logging for debug purposes
# set_smart: CPU set to conservative gov, max 1344 MHz, sampling 2.5Hz
# set_performance: CPU set to performance gov @ 1344 MHz
# set_overclock: CPU set to performance gov @ 1512 MHz
# setting_get: get value of key from /mnt/SDCARD/spruce/settings/spruce.cfg
# setting_update: set value of key in /mnt/SDCARD/spruce/settings/spruce.cfg
# settings_organize: sort and clean up /mnt/SDCARD/spruce/settings/spruce.cfg

# vibrate: Vibrates the device for a specified duration

# This is a collection of functions that are used in multiple scripts
# Please do not add any dependencies here, this file is meant to be self-contained
# Keep methods in alphabetical order

# Gain access to the helper variables by adding this to the top of your script:
# . /mnt/SDCARD/spruce/scripts/helperFunctions.sh

DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin/display_text.elf"
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

# Export for enabling SSL support in CURL
export SSL_CERT_FILE=/mnt/SDCARD/miyoo/app/ca-certificates.crt

# Key exports so we can refer to buttons by more memorable names
export B_LEFT="key 1 105"
export B_RIGHT="key 1 106"
export B_UP="key 1 103"
export B_DOWN="key 1 108"

export B_A="key 1 57"
export B_B="key 1 29"
export B_X="key 1 42"
export B_Y="key 1 56"

export B_L1="key 1 15"
export B_L2="key 1 18"
export B_R1="key 1 14"
export B_R2="key 1 20"

export B_START="key 1 28"
export B_START_2="enter_pressed" # only registers 0 on release, no 1 on press
export B_SELECT="key 1 97"
export B_SELECT_2="rctrl_pressed"

export B_VOLUP="volume up"       # only registers on press and on change, not on release. No 1 or 0.
export B_VOLDOWN="key 1 114"     # has actual key codes like the buttons
export B_VOLDOWN_2="volume down" # only registers on change. No 1 or 0.
export B_MENU="key 1 1"          # surprisingly functions like a regular button

# Call this just by having "acknowledge" in your script
# This will pause until the user presses the A, B, or Start button
acknowledge() {
    # These echo's are needed to seperate the events in the key press log file
    local messages_file="/var/log/messages"
    echo "ACKNOWLEDGE $(date +%s)" >>"$messages_file"

    while true; do
        inotifywait "$messages_file"
        last_line=$(tail -n 1 "$messages_file")
        case "$last_line" in
        *"$B_START_2"* | *"$B_A"* | *"$B_B"*)
            echo "ACKNOWLEDGED $(date +%s)" >>"$messages_file"
            log_message "last_line: $last_line" -vS
            break
            ;;
        esac
    done
}

auto_regen_tmp_update() {
    tmp_dir="/mnt/SDCARD/.tmp_update"
    updater="/mnt/SDCARD/spruce/scripts/.tmp_update/updater"
    if ! flag_check "tmp_update_repair_attempted"; then
        [ ! -d "$tmp_dir" ] && mkdir "$tmp_dir" && flag_add "tmp_update_repair_attempted" && log_message ".tmp_update folder repair attempted. Adding tmp_update_repair_attempted flag."
        [ ! -f "$tmp_dir/updater" ] && cp "$updater" "$tmp_dir/updater"
    fi
}

check_and_connect_wifi() {
    # ########################################################################
    # WARNING: Avoid running this function in-game, it will lead to stuttters!
    # ########################################################################

    messages_file="/var/log/messages"
    
    # More thorough connection check
    connection_active=0
    if ifconfig wlan0 | grep -qE "inet |inet6 "; then
        # Additional validation - try to ping a reliable host
        if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
            connection_active=1
            log_message "Active WiFi connection verified"
        else
            log_message "WiFi interface has IP but no connectivity - attempting reconnect"
            ifconfig wlan0 down  # Force a reconnection attempt
            connection_active=0
        fi
    fi
    
    if [ $connection_active -eq 0 ]; then
        log_message "Attempting to connect to WiFi"

        # Bring the existing interface down cleanly if its running
        ifconfig wlan0 down
        killall wpa_supplicant
        killall udhcpc

        # Restart the interface and try to connect
        ifconfig wlan0 up
        wpa_supplicant -B -i wlan0 -c /config/wpa_supplicant.conf
        udhcpc -i wlan0 &

        display --icon "/mnt/SDCARD/spruce/imgs/signal.png" -t "Waiting to connect....
Press START to continue anyway."
        {
            while true; do
                if ifconfig wlan0 | grep -qE "inet |inet6 " && ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
                    echo "Successfully connected to WiFi" >> "$messages_file"
                    break
                fi
                sleep 0.5
            done
        } &
        while true; do
            inotifywait "$messages_file"
            last_line=$(tail -n 1 "$messages_file")
            case $last_line in
            *"$B_START"* | *"$B_START_2"*)
                log_message "WiFi connection cancelled by user"
                display_kill
                return 1
                ;;
            *"Successfully connected to WiFi"*)
                log_message "Successfully connected to WiFi"
                display_kill
                return 0
                ;;
            esac
        done
    fi
    
    return 0
}

# Call this to wait for the user to confirm an action
# Use this with display --confirm to show an image with a confirm/cancel prompt
# The combined usage would be like

# display -t "Do you want to do this?" --confirm
# if confirm; then
#     display -t "You confirmed the action" -d 3
# else
#     log_message "User did not confirm" -v
#     display -t "You did not confirm the action" -d 3
# fi
confirm() {
    local messages_file="/var/log/messages"
    local timeout=${1:-0}        # Default to 0 (no timeout) if not provided
    local timeout_return=${2:-1} # Default to 1 if not provided
    local start_time=$(date +%s)

    echo "CONFIRM $(date +%s)" >>"$messages_file"

    while true; do
        # Check for timeout
        if [ $timeout -ne 0 ]; then
            local current_time=$(date +%s)
            local elapsed_time=$((current_time - start_time))
            if [ $elapsed_time -ge $timeout ]; then
                display_kill
                echo "CONFIRM TIMEOUT $(date +%s)" >>"$messages_file"
                return $timeout_return
            fi
        fi

        # Wait for log message update (with a 1-second timeout)
        if ! inotifywait -t 1000 "$messages_file"; then
            continue
        fi

        # Get the last line of log file
        last_line=$(tail -n 1 "$messages_file")
        case "$last_line" in
        # B button - cancel
        *"key 1 29"*)
            # dismiss notification screen
            display_kill
            # exit script
            echo "CONFIRM CANCELLED $(date +%s)" >>"$messages_file"
            return 1
            ;;
        # A button - confirm
        *"key 1 57"*)
            # dismiss notification screen
            display_kill
            # exit script
            echo "CONFIRM CONFIRMED $(date +%s)" >>"$messages_file"
            return 0
            ;;
        esac
    done
}

# Call this to set the number of CPU cores to be online
# Usage: cores_online [number of cores]
# Default is 4 cores (all cores online)
cores_online() {
    local min_cores=4                # Minimum number of cores to keep online
    local num_cores=${1:-$min_cores} # Default to min_cores if no argument is provided

    # Ensure the input is between min_cores and 4
    if [ "$num_cores" -lt "$min_cores" ]; then
        num_cores=$min_cores
    elif [ "$num_cores" -gt 4 ]; then
        num_cores=4
    fi

    echo "Setting $num_cores CPU core(s) online"

    # Always keep CPU0 online
    echo 1 >/sys/devices/system/cpu/cpu0/online

    # Set the state for CPU1-3 based on num_cores
    for i in 1 2 3; do
        if [ "$i" -lt "$num_cores" ]; then
            echo 1 >/sys/devices/system/cpu/cpu$i/online
        else
            echo 0 >/sys/devices/system/cpu/cpu$i/online
        fi
    done
}

# Call this to dim the screen
# Call it as a background process
dim_screen() {
    local start_brightness=40
    local end_brightness=10
    local steps=90   # Total number of steps for the transition
    local delay=0.01 # 50ms delay between each step

    # Check if another dim_screen is running
    if pgrep -f "dim_screen" | grep -v $$ >/dev/null; then
        log_message "Another dim_screen process is already running" -v
        return 1
    fi

    # Get current brightness
    local current_brightness=$(cat /sys/devices/virtual/disp/disp/attr/lcdbl)

    # Check if we're already at target brightness
    if [ "$current_brightness" -eq "$end_brightness" ]; then
        log_message "Screen already at target brightness" -v
        return 0
    fi

    # Calculate the brightness decrease per step
    local brightness_range=$((start_brightness - end_brightness))
    local current=$start_brightness

    while [ $current -gt $end_brightness ]; do
        echo $current >/sys/devices/virtual/disp/disp/attr/lcdbl
        current=$((current - 1))
        sleep $delay
    done
}

DEFAULT_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayText.png"
ACKNOWLEDGE_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayAcknowledge.png"
CONFIRM_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayConfirm.png"
DEFAULT_FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"
# Call this to display text on the screen
# IF YOU CALL THIS YOUR SCRIPT NEEDS TO CALL display_kill()
# It's possible to leave a display process running
# Usage: display [options]
# Options:
#   -i, --image <path>    Image path (default: DEFAULT_IMAGE)
#   -t, --text <text>     Text to display
#   -d, --delay <seconds> Delay in seconds (default: 0)
#   -s, --size <size>     Text size (default: 36)
#   -p, --position <pos>  Text position in pixels from the top of the screen
#   (Text is offset from it's center, images are offset from the top of the image)
#   -a, --align <align>   Text alignment (left, middle, right) (default: middle)
#   -w, --width <width>   Text width (default: 600)
#   -c, --color <color>   Text color in RGB format (default: dbcda7) Spruce text yellow
#   -f, --font <path>     Font path (optional)
#   -o, --okay            Use ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE and runs acknowledge()
#   -bg, --bg-color <color> Background color in RGB format (default: 7f7f7f)
#   -bga, --bg-alpha <alpha> Background alpha value (0-255, default: 0)
#   -is, --image-scaling <scale> Image scaling factor (default: 1.0)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000
# Calling display with -o/--okay will use the ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE
# Calling display with --confirm will use the CONFIRM_IMAGE instead of DEFAULT_IMAGE
# If using --confirm, you should call the confirm() message in an if block in your script
# --confirm will supercede -o/--okay
# You can also call infinite image layers with (next-image.png scale height side)*
#   --icon <path>         Path to an icon image to display on top (default: none)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000 --icon "/path/to/icon.png"

display() {
    local image="$DEFAULT_IMAGE" text=" " delay=0 size=30 position=210 align="middle" width=600 color="ebdbb2" font=""
    local use_acknowledge_image=false
    local use_confirm_image=false
    local run_acknowledge=false
    local bg_color="7f7f7f" bg_alpha=0 image_scaling=1.0
    local icon_image=""
    local additional_images=""
    local position_set=false
    local qr_url=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--image) image="$2"; shift ;;
            -t|--text) text="$2"; shift ;;
            -d|--delay) delay="$2"; shift ;;
            -s|--size) size="$2"; shift ;;
            -p|--position) position="$2"; position_set=true; shift ;;
            -a|--align) align="$2"; shift ;;
            -w|--width) width="$2"; shift ;;
            -c|--color) color="$2"; shift ;;
            -f|--font) font="$2"; shift ;;
            -o|--okay) use_acknowledge_image=true; run_acknowledge=true ;;
            --confirm) use_confirm_image=true; use_acknowledge_image=false; run_acknowledge=false ;;
            -bg|--bg-color) bg_color="$2"; shift ;;
            -bga|--bg-alpha) bg_alpha="$2"; shift ;;
            -is|--image-scaling) image_scaling="$2"; shift ;;
            --icon) 
                icon_image="$2"
                if ! $position_set; then
                    position=$((position + 80))
                fi
                shift 
                ;;
            --add-image) 
                additional_images="$additional_images \"$2\" $3 $4 $5"
                shift 4
                ;;
            --qr)
                qr_url="$2"
                if ! $position_set; then
                    position=$((position + 85))
                fi
                shift
                ;;
            *) log_message "Unknown option: $1"; return 1 ;;
        esac 
        shift
    done
    local r="${color:0:2}"
    local g="${color:2:2}"
    local b="${color:4:2}"
    local bg_r="${bg_color:0:2}"
    local bg_g="${bg_color:2:2}"
    local bg_b="${bg_color:4:2}"

    # Set font to DEFAULT_FONT if it's empty
    if [ -z "$font" ]; then
        font="$DEFAULT_FONT"
    fi

    # Construct the command
    local command="$DISPLAY_TEXT_FILE \"$image\" \"$text\" $delay $size $position $align $width $r $g $b \"$font\" $bg_r $bg_g $bg_b $bg_alpha $image_scaling"

    # Add icon image if specified
    if [ -n "$icon_image" ]; then
        command="$command \"$icon_image\" 0.20 160 middle"
    fi

    # Add CONFIRM_IMAGE if --confirm flag is used, otherwise use ACKNOWLEDGE_IMAGE if --okay flag is used
    if [[ "$use_confirm_image" = true ]]; then
        command="$command \"$CONFIRM_IMAGE\" 1.0 240 middle"
        delay=0
    elif [[ "$use_acknowledge_image" = true ]]; then
        command="$command \"$ACKNOWLEDGE_IMAGE\" 1.0 240 middle"
    fi

    # Add additional images
    if [ -n "$additional_images" ]; then
        command="$command $additional_images"
    fi

    # Generate QR code if --qr flag is used
    if [ -n "$qr_url" ]; then
        qr_image=$(qr_code -t "$qr_url")
        if [ -n "$qr_image" ]; then
            command="$command \"$qr_image\" 0.50 140 middle"
        else
            log_message "Failed to generate QR code for URL: $qr_url" -v
        fi
    fi

    display_kill

    # Execute the command in the background if delay is 0
    if [[ "$delay" -eq 0 ]]; then
        eval "$command" &
        log_message "display command: $command" -v
        # Run acknowledge if -o or --okay was used and --confirm was not used
        if [[ "$run_acknowledge" = true && "$use_confirm_image" = false ]]; then
            acknowledge
        fi
    else
        # Execute the command and capture its output
        eval "$command"
        log_message "display command: $command" -v
    fi
}

# Call this to kill any display processes left running
# If you use display() at all you need to call this on all the possible exits of your script
display_kill() {
    kill -9 $(pgrep display)
}

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

# Add a flag
# Usage: flag_add "flag_name"
flag_add() {
    local flag_name="$1"
    touch "$FLAGS_DIR/${flag_name}.lock"
}

# Remove a flag
# Usage: flag_remove "flag_name"
flag_remove() {
    local flag_name="$1"
    rm -f "$FLAGS_DIR/${flag_name}.lock"
}

# Call this to get the last button pressed
# Returns the name of the button pressed, or "" if no matching button was pressed
# Returned strings are simplified, so "B_L1" would return "L1"
get_button_press() {
    local button_pressed=""
    local timeout=500 # Timeout in seconds
    for i in $(seq 1 $timeout); do
        local last_line=$(tail -n 1 /var/log/messages)
        case "$last_line" in
        *"$B_L1 1"*) button_pressed="L1" ;;
        *"$B_L2 1"*) button_pressed="L2" ;;
        *"$B_R1 1"*) button_pressed="R1" ;;
        *"$B_R2 1"*) button_pressed="R2" ;;
        *"$B_X 1"*) button_pressed="X" ;;
        *"$B_A 1"*) button_pressed="A" ;;
        *"$B_B 1"*) button_pressed="B" ;;
        *"$B_Y 1"*) button_pressed="Y" ;;
        *"$B_UP 1"*) button_pressed="UP" ;;
        *"$B_DOWN 1"*) button_pressed="DOWN" ;;
        *"$B_LEFT 1"*) button_pressed="LEFT" ;;
        *"$B_RIGHT 1"*) button_pressed="RIGHT" ;;
        *"$B_START 1"*) button_pressed="START" ;;
        *"$B_SELECT 1"*) button_pressed="SELECT" ;;
        esac

        if [ -n "$button_pressed" ]; then
            echo "$button_pressed"
            return 0
        fi
        sleep 0.1
    done
    echo "B"
}

get_event() {
    "/mnt/SDCARD/spruce/bin/getevent" /dev/input/event3
}

get_version() {
    local spruce_file="/mnt/SDCARD/spruce/spruce"

    if [ ! -f "$spruce_file" ]; then
        echo "0"
        return 1
    fi

    local version=$(cat "$spruce_file" | tr -d '[:space:]')

    if [ -z "$version" ]; then
        echo "0"
        return 1
    fi

    # Check if the returned version is in the correct format
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)*$'; then
        echo "$version"
        return 0
    else
        echo "0"
        return 1
    fi
}

get_version_nightly() {
    local base_version=$(get_version)
    
    # Ensure we got a valid base version
    if [ -z "$base_version" ] || [ "$base_version" = "0" ]; then
        echo "$base_version"
        return 1
    fi
    
    local nightly_pattern="/mnt/SDCARD/${base_version}-*"
    
    # List all matching files and log them
    local matching_files=$(ls $nightly_pattern 2>/dev/null)
    
    # Find any matching nightly version file
    local nightly_file=$(ls $nightly_pattern 2>/dev/null | head -n 1)
    
    if [ -n "$nightly_file" ]; then
        local nightly_version=$(basename "$nightly_file")
        echo "$nightly_version"
    else
        echo "$base_version"
    fi
}

# Call this to toggle verbose logging
# After this is called, any log_message calls will output to the log file if -v is passed
# USE THIS ONLY WHEN DEBUGGING, IT WILL GENERATE A LOT OF LOG FILE ENTRIES
# Remove it from your script when done.
# Can be used as a toggle: calling it once enables verbose logging, calling it again disables it
log_verbose() {
    local calling_script=$(basename "$0")
    if flag_check "log_verbose"; then
        flag_remove "log_verbose"
        log_message "Verbose logging disabled in script: $calling_script"
    else
        flag_add "log_verbose"
        log_message "Verbose logging enabled in script: $calling_script"
    fi
}

# Call this like:
# log_message "Your message here"
# To output to a custom log file, set the variable within your script:
# log_file="/mnt/SDCARD/App/MyApp/spruce.log"
# This will log the message to the spruce.log file in the Saves/spruce folder
#
# Usage examples:
# Log a regular message:
#    log_message "This is a regular log message"
# Log a verbose message (only logged if log_verbose was called):
#    log_message "This is a verbose log message" -v
# Log to a custom file:
#    log_message "Custom file log message" "" "/path/to/custom/log.file"
# Log a verbose message to a custom file:
#    log_message "Verbose custom file log message" -v "/path/to/custom/log.file"
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

log_precise() {
    local message="$1"
    local date_part=$(date '+%Y-%m-%d %H:%M:%S')
    local uptime_part=$(cut -d ' ' -f 1 /proc/uptime)
    local timestamp="${date_part}.${uptime_part#*.}"
    printf '%s %s\n' "$timestamp" "$message" >>"$log_file"
}

# Generate a QR code
# Usage: qr_code -t "text" -s "size" -l "level" -o "output"
# If no output is provided, the QR code will be saved to /tmp/tmp/qr.png
#   QR_CODE=$(qr_code -t "https://www.google.com")
#   display -i "$QR_CODE" -t "DT: QR Code" -d 5
QRENCODE_PATH="/mnt/SDCARD/miyoo/app/qrencode"
qr_code() {
    local text=""
    local size=3
    local level="M"
    local output="/mnt/SDCARD/spruce/tmp/qr.png"
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -t|--text) text="$2"; shift ;;
            -s|--size) size="$2"; shift ;;
            -l|--level) level="$2"; shift ;;
            -o|--output) output="$2"; shift ;;
            *) text="$1" ;;  # If no flag, assume it's the text
        esac
        shift
    done
    
    # Ensure text is provided
    if [ -z "$text" ]; then
        log_message "QR Code error: No text provided" -v
        return 1
    fi
    
    # Make tmp directory if it doesn't exist
    mkdir -p "/mnt/SDCARD/spruce/tmp"

    # Generate QR code
    if "$QRENCODE_PATH" -o "$output" -s "$size" -l "$level" -m 2 "$text" >/dev/null 2>&1; then
        echo "$output"
        return 0
    else
        log_message "QR Code generation failed"
        echo ""
        return 1
    fi
}

read_only_check() {
    if [ $(mount | grep SDCARD | cut -d"(" -f 2 | cut -d"," -f1 ) == "ro" ]; then
        log_message "SDCARD is mounted read-only, remounting as read-write"
        mount -o remount,rw /dev/mmcblk0p1 /mnt/SDCARD
        log_message "SDCARD remounted as read-write"
    fi
}

set_smart() {
    cores_online
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo conservative >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo 35 >/sys/devices/system/cpu/cpufreq/conservative/down_threshold
    echo 70 >/sys/devices/system/cpu/cpufreq/conservative/up_threshold
    echo 3 >/sys/devices/system/cpu/cpufreq/conservative/freq_step
    echo 1 >/sys/devices/system/cpu/cpufreq/conservative/sampling_down_factor
    echo 400000 >/sys/devices/system/cpu/cpufreq/conservative/sampling_rate
    echo "$scaling_min_freq" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    log_message "CPU Mode now locked to SMART" -v
}

set_performance() {
    cores_online
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo performance >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    log_message "CPU Mode now locked to PERFORMANCE" -v

}

set_overclock() {
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    /mnt/SDCARD/miyoo/utils/utils "performance" 4 1512 384 1080 1
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    log_message "CPU Mode now locked to OVERCLOCK" -v
}

CFG_FILE="/mnt/SDCARD/spruce/settings/spruce.cfg"

# For simple settings that use 0/1 putting this in an if statement is the easiest usage
# For complex values, you can use setting_get and then use the value in your script by capturing it
# For example:
#    VALUE=$(setting_get "my_setting")
#    if [ "$VALUE" = "complex value" ]; then
#        do complex tasks
#    fi
setting_get() {
    [ $# -eq 1 ] || return 1
    value=$(grep "^$1=" "$CFG_FILE" | cut -d'=' -f2)
    if [ -z "$value" ]; then
        echo ""
        return 1
    else
        echo "$value"
        # Return 1 if value is "1", 0 otherwise
        [ "$value" = "1" ] && return 1
        return 0
    fi
}

setting_update() {
    [ $# -eq 2 ] || return 1
    key="$1"
    value="$2"

    case "$value" in
    "on" | "true" | "1") value=0 ;;
    "off" | "false" | "0") value=1 ;;
    esac

    if grep -q "^$key=" "$CFG_FILE"; then
        sed -i "s/^$key=.*/$key=$value/" "$CFG_FILE"
    else
        # Ensure there's a newline at the end of the file before appending
        sed -i -e '$a\' "$CFG_FILE"
        echo "$key=$value" >>"$CFG_FILE"
    fi
}

settings_organize() {
    # Create a temporary file
    temp_file=$(mktemp)

    # Sort the file, remove empty lines, and preserve a single newline at the end
    sort "$CFG_FILE" | sed '/^$/d' | sed '$a\' >"$temp_file"

    # Replace the original file with the sorted and cleaned version
    mv "$temp_file" "$CFG_FILE"

    log_message "Settings file organized and cleaned up" -v
}

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
    local duration=50
    local intensity

    # Parse arguments in any order
    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    # If no intensity was specified, get from settings
    if [ -z "$intensity" ]; then
        intensity="$(setting_get "rumble_intensity")"
    fi

    if [ "$intensity" = "Strong" ]; then
        echo "$duration" >/sys/devices/virtual/timed_output/vibrator/enable
    elif [ "$intensity" = "Medium" ]; then
        timer=0
        while [ $timer -lt $duration ]; do
            echo 5 >/sys/devices/virtual/timed_output/vibrator/enable
            sleep 0.006
            timer=$(($timer + 6))
        done &
    elif [ "$intensity" = "Weak" ]; then
        timer=0
        while [ $timer -lt $duration ]; do
            echo 3 >/sys/devices/virtual/timed_output/vibrator/enable
            sleep 0.004
            timer=$(($timer + 4))
        done &
    else
        log_message "this is where I'd put my vibration... IF I HAD ONE"
    fi
}



