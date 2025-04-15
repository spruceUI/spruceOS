#!/bin/sh

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
# get_current_theme: Unlocks dynamic variables for fast access to assets of current theme
# get_current_theme_path: Returns path of the current theme
# log_message: Logs a message to a file
# log_precise: Logs messages with greater precision for performance testing
# log_verbose: Turns on or off verbose logging for debug purposes
# set_smart: CPU set to conservative gov, max 1344 MHz for A30, 1800MHz for Flip/Brick, sampling 2.5Hz
# set_performance: CPU set to performance gov @ 1344 MHz for A30, 1800MHz for Flip/Brick
# set_overclock: CPU set to performance gov @ 1512 MHz for A30, 1992MHz for Flip/Brick
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

# Export for architecture (aarch64 or armv7l)
export ARCH="$(uname -m)"

# Export for enabling SSL support in CURL
export SSL_CERT_FILE=/mnt/SDCARD/miyoo/app/ca-certificates.crt

# Detect device and export to any script sourcing helperFunctions
INFO=$(cat /proc/cpuinfo 2> /dev/null)
log_message "[helperFunctions.sh] $INFO" -v

case $INFO in
*"sun8i"*)
	export PLATFORM="A30"
    ;;
*"TG5040"*)
	export PLATFORM="SmartPro"
	;;
*"TG3040"*)
	export PLATFORM="Brick"
	;;
*"0xd05"*)
    export PLATFORM="Flip"
    ;;
*)
    export PLATFORM="A30"
    ;;
esac

log_message "[helperFunctions.sh] Platform is $PLATFORM"
. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg

if [ "$ARCH" = "aarch64" ]; then
    export PATH="/mnt/SDCARD/spruce/bin64:$PATH" # 64-bit
else
    export PATH="/mnt/SDCARD/spruce/bin:$PATH" # 32-bit
fi

# Key exports so we can refer to buttons by more memorable names
if [ "$PLATFORM" = "A30" ]; then
    export B_POWER="1 116"

    export B_LEFT="1 105 1"
    export B_RIGHT="1 106 1"
    export B_UP="1 103 1"
    export B_DOWN="1 108 1"

    export B_A="1 57"
    export B_B="1 29"
    export B_X="1 42"
    export B_Y="1 56"

    export B_L1="1 15"
    export B_L2="1 18"
    export B_R1="1 14"
    export B_R2="1 20"

    export B_START="1 28"
    export B_START_2="enter_pressed" # only registers 0 on release, no 1 on press
    export B_SELECT="1 97"
    export B_SELECT_2="rctrl_pressed"

    export B_VOLUP="volume up"       # only registers on press and on change, not on release. No 1 or 0.
    export B_VOLDOWN="1 114"     # has actual key codes like the buttons
    export B_VOLDOWN_2="volume down" # only registers on change. No 1 or 0.
    export B_MENU="1 1"          # surprisingly functions like a regular button

elif [ "$PLATFORM" = "Brick" ] || [ $PLATFORM = "SmartPro" ] || [ "$PLATFORM" = "Flip" ]; then
    export B_POWER="1 116"
    
    export B_LEFT="3 16 -1"  # negative for left
    export B_RIGHT="3 16 1"  # positive for right
    export B_UP="3 17 -1"    # negative for up
    export B_DOWN="3 17 1"   # positive for down

    export B_A="1 305"
    export B_B="1 304"
    export B_X="1 308"
    export B_Y="1 307"

    export B_L1="1 310"
    export B_L2="3 2 2" # 255 on push, 0 on release
    export B_R1="1 311"
    export B_R2="3 5" # 255 on push, 0 on release

    export B_L3="1 317" # also logs left fnkey stuff
    export B_R3="1 318" # also logs right fnkey stuff

    export B_START="1 315"
    export B_START_2="start_pressed" # only registers 0 on release, no 1.
    export B_SELECT="1 314"
    export B_SELECT_2="select_pressed" # registers both 1 and 0

    export B_VOLUP="1 115" # has actual key codes like the buttons
    export B_VOLUP_2="volume up" # only registers 0 on release, no 1.
    export B_VOLDOWN="1 114" # has actual key codes like the buttons
    export B_VOLDOWN_2="volume down" # only registers 0 on release, no 1.
    export B_MENU="1 316"

    export STICK_LEFT="3 0 -32767" # negative for left
    export STICK_RIGHT="3 0 32767" # positive for right
    export STICK_UP="3 1 -32767"   # negative for up
    export STICK_DOWN="3 1 32767"  # positive for down

    export STICK_LEFT_2="3 4 -32767" # negative for left
    export STICK_RIGHT_2="3 4 32767" # positive for right
    export STICK_UP_2="3 3 -32767"   # negative for up
    export STICK_DOWN_2="3 3 32767"  # positive for down

    if [ ! "$PLATFORM" = "SmartPro" ]; then
        export PYSDL2_DLL_PATH="/mnt/sdcard/MIYOO_EX/site-packages/sdl2dll/dll"
        export PATH="/mnt/sdcard/MIYOO_EX/bin/:$PATH"
        export HOME="/mnt/sdcard"
    fi

    if [ "$PLATFORM" = "Flip" ]; then
        export B_START="1 315"
        export B_SELECT="1 314"
    fi

fi

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
        *"key $B_START_2"* | *"key $B_A"* | *"key $B_B"*)
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
    local timeout=30  # Think about making this configurable
    local start_time=$(date +%s)

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
        if [ ! -f /mnt/sdcard/Saves/.disablesprucewifi ]; then
            ifconfig wlan0 down
            killall wpa_supplicant
            killall udhcpc

            # Restart the interface and try to connect
            ifconfig wlan0 up
            wpa_supplicant -B -i wlan0 -c /config/wpa_supplicant.conf
            udhcpc -i wlan0 &
        else
            log_message "Letting stock OS restart wifi due to existance of /mnt/sdcard/Saves/.disablesprucewifi"
        fi
		
        display --icon "/mnt/SDCARD/spruce/imgs/signal.png" -t "Waiting to connect....
Press START to continue anyway."
        {
            while true; do
                # Check for timeout
                current_time=$(date +%s)
                if [ $((current_time - start_time)) -ge $timeout ]; then
                    echo "WiFi connection timed out" >> "$messages_file"
                    break
                fi

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
            *"WiFi connection timed out"*)
                log_message "WiFi connection timed out after $timeout seconds"
                display_kill
                return 1
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
        # Check for timeout first
        if [ $timeout -ne 0 ]; then
            local current_time=$(date +%s)
            local elapsed_time=$((current_time - start_time))
            if [ $elapsed_time -ge $timeout ]; then
                display_kill
                echo "CONFIRM TIMEOUT $(date +%s)" >>"$messages_file"
                return $timeout_return
            fi
        fi

        # Wait for log message update (with a shorter timeout to allow frequent timeout checks)
        if ! inotifywait -t 1 "$messages_file" >/dev/null 2>&1; then
            continue
        fi

        # Get the last line of log file
        last_line=$(tail -n 1 "$messages_file")
        case "$last_line" in
        # B button - cancel
        *"$B_B"*)
            display_kill
            echo "CONFIRM CANCELLED $(date +%s)" >>"$messages_file"
            return 1
            ;;
        # A button - confirm
        *"$B_A"*)
            display_kill
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
    chmod a+w /sys/devices/system/cpu/cpu0/online
    echo 1 >/sys/devices/system/cpu/cpu0/online
    chmod a-w /sys/devices/system/cpu/cpu0/online

    # Set the state for CPU1-3 based on num_cores
    for i in 1 2 3; do
        chmod a+w /sys/devices/system/cpu/cpu$i/online
        if [ "$i" -lt "$num_cores" ]; then
            echo 1 >/sys/devices/system/cpu/cpu$i/online
        else
            echo 0 >/sys/devices/system/cpu/cpu$i/online
        fi
        chmod a-w /sys/devices/system/cpu/cpu$i/online
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

[ "$PLATFORM" = "SmartPro" ] && DEFAULT_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayTextWidescreen.png" || DEFAULT_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayText.png"
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
#   -p, --position <pos>  Text position as percentage from the top of the screen
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
    local screen_width=640 screen_height=480 rotation=0
    local ld_library_path="$LD_LIBRARY_PATH"
    local width=600
    if [ "$PLATFORM" = "Brick" ]; then
      # TODO: we might want to move these to config files?
      screen_width=1024
      screen_height=768
      rotation=0
      width=960
      # TODO: this should go away once profile is wired up for the brick
      ld_library_path="/usr/trimui/lib:$ld_library_path"
      # TODO: we might want to make this more generic based on architecture eventually
    elif [ "$PLATFORM" = "SmartPro" ]; then
      # TODO: we might want to move these to config files?
      screen_width=1280
      screen_height=720
      rotation=0
      width=1200
      # TODO: this should go away once profile is wired up for the brick
      ld_library_path="/usr/trimui/lib:$ld_library_path"
      # TODO: we might want to make this more generic based on architecture eventually
      DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin64/display_text.elf"
    elif [ "$PLATFORM" = "Flip" ]; then
      # TODO: we might want to move these to config files?
      screen_width=640
      screen_height=480
      rotation=0
      width=600
      # TODO: we might want to make this more generic based on architecture eventually
      DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin64/display_text.elf"
    elif [ "$PLATFORM" = "A30" ]; then
      screen_width=640
      screen_height=480
      rotation=270
      width=600
    fi

    local image="$DEFAULT_IMAGE" text=" " delay=0 size=30 position=70 align="middle" color="ebdbb2" font=""
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
                    position=89
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


    local command="LD_LIBRARY_PATH=\"$ld_library_path\" $DISPLAY_TEXT_FILE "
    command="$command""$screen_width $screen_height $rotation "

    # Construct the command
    local command="$command""\"$image\" \"$text\" $delay $size $position $align $width $r $g $b \"$font\" $bg_r $bg_g $bg_b $bg_alpha $image_scaling"

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

# Get the full path to a flag file
# Usage: flag_path "flag_name"
# Returns the full path to the flag file (with .lock extension)
flag_path() {
    local flag_name="$1"
    echo "$FLAGS_DIR/${flag_name}.lock"
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
    local messages_file="/var/log/messages"
    local button_pressed=""
    local timeout=${1:-180}  # Default 180 second timeout if not specified
    local start_time=$(date +%s)

    echo "GET_BUTTON_PRESS $(date +%s)" >>"$messages_file"

    while true; do
        # Check for timeout
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        if [ $elapsed_time -ge $timeout ]; then
            echo "GET_BUTTON_PRESS TIMEOUT $(date +%s)" >>"$messages_file"
            echo "B"
            return 1
        fi

        # Wait for log message update
        if ! inotifywait -t 1 "$messages_file" >/dev/null 2>&1; then
            continue
        fi

        # Get the last line of log file
        local last_line=$(tail -n 1 "$messages_file")
        case "$last_line" in
            *"$B_L1"*) button_pressed="L1" ;;
            *"$B_L2"*) button_pressed="L2" ;;
            *"$B_R1"*) button_pressed="R1" ;;
            *"$B_R2"*) button_pressed="R2" ;;
            *"$B_X"*) button_pressed="X" ;;
	    # this is firing on keydown and keyup, leading to duplicate presses being recognized
	    # should this be fixed in somewhere else?
            *"$B_A 1"*) button_pressed="A" ;;
            *"$B_B 1"*) button_pressed="B" ;;
            *"$B_Y"*) button_pressed="Y" ;;
            *"$B_UP"*) button_pressed="UP" ;;
            *"$B_DOWN"*) button_pressed="DOWN" ;;
            *"$B_LEFT"*) button_pressed="LEFT" ;;
            *"$B_RIGHT"*) button_pressed="RIGHT" ;;
            *"$B_START"*) button_pressed="START" ;;
            *"$B_START_2"*) button_pressed="START" ;;
            *"$B_SELECT"*) button_pressed="SELECT" ;;
            *"$B_SELECT_2"*) button_pressed="SELECT" ;;
        esac

        if [ -n "$button_pressed" ]; then
            echo "GET_BUTTON_PRESS RECEIVED $button_pressed $(date +%s)" >>"$messages_file"
            echo "$button_pressed"
            return 0
        fi
    done
}

# Returns the path of the current theme
# Use by doing        theme_path=$(get_current_theme_path)
# Use files inside themes to make your apps!
get_current_theme_path() {

    # check if config file exists
    if [ ! -f "$SYSTEM_JSON" ]; then
        echo "Error: Configuration file not found at $SYSTEM_JSON"
        return 1
    fi

    # Extract "theme" from JSON, ignoring errors
    local theme_name
    theme_name=$(jq -r '.theme' "$SYSTEM_JSON")

    # If "theme" is empty
    if [ -z "$theme_name" ]; then
        echo "Error: Could not retrieve theme name from $SYSTEM_JSON"
        return 1
    fi

    echo "$theme_name"
}

# To support themes in your apps do         [   eval "$(get_current_theme)"    ]
# Doing this will unlock dynamic variables that will give you fast access to some
# common theme files and values. These dynamic variable are: $THEME_PATH, $THEME_BG etc.
#
# Code example:
#
# eval "$(get_current_theme)"
# echo "Current theme path:         $THEME_PATH"
# echo "Background image path:      $THEME_BG"
# echo "Font path:                  $THEME_FONT"
# echo "Font size:                  $THEME_FONT_SIZE"
# echo "Font color:                 $THEME_FONT_COLOR"
# echo "Left arrow icon:            $THEME_LEFT"
# echo "Right arrow icon:           $THEME_RIGHT"
# echo "Logo:                       $THEME_LOGO"
# echo "OK icon:                    $THEME_OK"
# echo "Home button icon:           $THEME_HOME"
# echo "A button icon:              $THEME_A"
# echo "B button icon:              $THEME_B"
# echo "L2 button icon:             $THEME_L2"
# echo "R2 button icon:             $THEME_R2"
# echo "X button icon:              $THEME_X"
# echo "Y button icon:              $THEME_Y"
# echo "START button icon:          $THEME_START"
# echo "Information icon:           $THEME_INFO"
# echo "Folder icon:                $THEME_FOLDER"
# echo "SD/TF card icon:            $THEME_SD"
# echo "Wifi icon:                  $THEME_WIFI"
# echo "Shutdown icon:              $THEME_SHUTDOWN"
# echo "Reset icon:                 $THEME_RESET"
# echo "Star icon:                  $THEME_STAR"
# echo "Expert Apps icon:           $THEME_EXPERT_APPS"
get_current_theme() {
    # gets current theme path
    local theme_path
    theme_path=$(get_current_theme_path)
    local json_path
    json_path="$theme_path/config.json"

    # checks if path exists
    if [ -d "$theme_path" ]; then
        # Export theme paths
        echo "THEME_PATH=\"$theme_path\""
        echo "THEME_BG=\"$theme_path/skin/background.png\""
        echo "THEME_LEFT=\"$theme_path/skin/icon-left-arrow-24.png\""
        echo "THEME_RIGHT=\"$theme_path/skin/icon-right-arrow-24.png\""
        echo "THEME_LOGO=\"$theme_path/skin/app-loading-05.png\"" #need to discuss this
        echo "THEME_OK=\"$theme_path/skin/icon-OK.png\""
        echo "THEME_HOME=\"$theme_path/skin/ic-MENU.png\""
        echo "THEME_A=\"$theme_path/skin/icon-A-54.png\""
        echo "THEME_B=\"$theme_path/skin/icon-B-54.png\""
        echo "THEME_L2=\"$theme_path/skin/icon-L2.png\""
        echo "THEME_R2=\"$theme_path/skin/icon-R2.png\""
        echo "THEME_X=\"$theme_path/skin/icon-x.png\""
        echo "THEME_Y=\"$theme_path/skin/icon-y.png\""
        echo "THEME_START=\"$theme_path/skin/icon-START.png\""
        echo "THEME_INFO=\"$theme_path/skin/icon-device-info-48.png\""
        echo "THEME_FOLDER=\"$theme_path/skin/icon-folder.png\""
        echo "THEME_SD=\"$theme_path/skin/icon-TF.png\""
        echo "THEME_WIFI=\"$theme_path/skin/icon-setting-wifi.png\""
        echo "THEME_SHUTDOWN=\"$theme_path/skin/icon-Shutdown.png\""
        echo "THEME_RESET=\"$theme_path/skin/icon-factory-reset-48.png\""
        echo "THEME_STAR=\"$theme_path/skin/nav-favorite-f.png\""
        echo "THEME_EXPERT_APPS=\"$theme_path/icons/App/expertappswitch.png\""

        # Extract values from config JSON using jq
        if [ -f "$json_path" ]; then
            THEME_FONT_TITLE=$(jq -r '.list.font' "$json_path")
            THEME_FONT="$theme_path/$THEME_FONT_TITLE"
            THEME_FONT_SIZE=$(jq -r '.list.size' "$json_path")
            THEME_FONT_COLOR=$(jq -r '.list.color' "$json_path")

            echo "THEME_FONT=\"$THEME_FONT\""
            echo "THEME_FONT_SIZE=\"$THEME_FONT_SIZE\""
            echo "THEME_FONT_COLOR=\"$THEME_FONT_COLOR\""
        else
            echo "Error: JSON config file not found at $json_path."
            return 1
        fi
    else
        echo "Error: theme located in $theme_path doesn't exist."
        return 1
    fi
}

#
#       restore_theme()
#
# This function returns the user's theme path if it's not the default theme
# Meant to be used on installations and updates only
get_theme_path_to_restore(){
    # Get the current theme path
    local current_theme_path=$(get_current_theme_path)
    local spruce_theme="/mnt/SDCARD/Themes/SPRUCE/"
    local default_theme="../res/"
    local default_theme_2="./"

    # if the current theme is equal to the default miyoo theme
    if [[ "$current_theme_path" == "$default_theme" ]]; then # that's ugly!
        echo "$spruce_theme"                                 # Switch to the spruce theme ASAP
    elif [[ "$current_theme_path" == "$default_theme_2" ]]; then # that's ugly!
        echo "$spruce_theme"                                     # Switch to the spruce theme ASAP
    else # If not, give back the user his loved theme <3
        echo "$current_theme_path"
    fi
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

    # Updated regex to handle both beta and nightly versions
    # e.g., 3.3.2-Beta or 3.3.1-20250123
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)*(-([A-Za-z]+|[0-9]{8}))?$'; then
        echo "$version"
        return 0
    else
        echo "0"
        return 1
    fi
}

get_version_complex() {
    local base_version=$(get_version)

    # Ensure we got a valid base version
    if [ -z "$base_version" ] || [ "$base_version" = "0" ]; then
        echo "$base_version"
        return 1
    fi

    local version_pattern="/mnt/SDCARD/${base_version}-*"
    
    # Find any matching version file (beta or nightly)
    local test_file=$(ls $version_pattern 2>/dev/null | head -n 1)

    if [ -n "$test_file" ]; then
        local test_version=$(basename "$test_file")
        echo "$test_version"
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
QRENCODE64_PATH="/mnt/SDCARD/spruce/bin64/qrencode"
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

    local qr_bin_path=$QRENCODE_PATH
    if [ ! "$PLATFORM" = "A30" ]; then
      qr_bin_path=$QRENCODE64_PATH
    fi

    # Generate QR code
    if "$qr_bin_path" -o "$output" -s "$size" -l "$level" -m 2 "$text" >/dev/null 2>&1; then
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

# Toggle screen recording with audio
# Usage: record_video [output_file] [timeout_minutes]
# If no output file is specified, defaults to /mnt/SDCARD/Roms/MEDIA/recording_YYYY-MM-DD_HH-MM-SS.mp4
# If no timeout is specified, defaults to 5 minutes
record_video() {
    if [ -f "/tmp/ffmpeg_recording.pid" ]; then
        # Stop recording if one is in progress
        vibrate 200
        local pid=$(cat "/tmp/ffmpeg_recording.pid")
        kill $pid 2>/dev/null
        rm "/tmp/ffmpeg_recording.pid"
        flag_remove "setting_cpu"
        log_message "Stopped recording" -v
        sleep 1
        display -t "Recording stopped" -d 3
    else
        # Start new recording
        local output_file="$1"
        local timeout_minutes="${2:-5}"  # Default to 5 minutes if not specified
        local date_str=$(date +%Y-%m-%d_%H-%M-%S)
        set_performance
        # Prevent the CPU from being clocked down while recording
        flag_add "setting_cpu"

        # If no output file specified, create one with timestamp
        if [ -z "$output_file" ]; then
            output_file="/mnt/SDCARD/Roms/MEDIA/recording_${date_str}.mp4"
        fi

        vibrate
        sleep 0.1
        vibrate
        # Start ffmpeg recording
        ffmpeg -f fbdev -framerate 30 -i /dev/fb0 -f alsa -ac 1 -i default \
            -c:v libx264 -filter:v "transpose=1" -preset ultrafast -b:v 1500k -pix_fmt yuv420p \
            -c:a aac -b:a 80k -ac 1 \
            -t $((timeout_minutes * 60)) "$output_file" &

        # Store PID for later use
        echo $! > "/tmp/ffmpeg_recording.pid"

        log_message "Started recording to: $output_file (timeout: ${timeout_minutes}m)" -v

        # Set up automatic stop after timeout
        (
            sleep $((timeout_minutes * 60))
            if [ -f "/tmp/ffmpeg_recording.pid" ]; then
                record_video
            fi
        ) &
    fi
}

set_smart() {
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online
        chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
        chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        case "$PLATFORM" in
            "A30") scaling_max_freq=1344000 CONSERVATIVE_POLICY_DIR="/sys/devices/system/cpu/cpufreq/conservative";;
            "Flip") scaling_max_freq=1800000 CONSERVATIVE_POLICY_DIR="/sys/devices/system/cpu/cpufreq/policy0/conservative";;
            "Brick" | "SmartPro") scaling_max_freq=1800000 CONSERVATIVE_POLICY_DIR="/sys/devices/system/cpu/cpufreq/conservative";;
        esac
        echo conservative >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        echo 35 >$CONSERVATIVE_POLICY_DIR/down_threshold
        echo 70 >$CONSERVATIVE_POLICY_DIR/up_threshold
        echo 3 >$CONSERVATIVE_POLICY_DIR/freq_step
        echo 1 >$CONSERVATIVE_POLICY_DIR/sampling_down_factor
        echo 400000 >$CONSERVATIVE_POLICY_DIR/sampling_rate
        echo "$scaling_min_freq" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
        echo $scaling_max_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
        chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        log_message "CPU Mode now locked to SMART" -v
        flag_remove "setting_cpu"
    fi
}

set_performance() {
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online
        chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        echo performance >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        case "$PLATFORM" in
            "A30") scaling_max_freq=1344000 ;;
            "Brick"|"Flip"|"SmartPro") scaling_max_freq=1800000 ;;
        esac
        echo $scaling_max_freq >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        log_message "CPU Mode now locked to PERFORMANCE" -v
        flag_remove "setting_cpu"
    fi
}

set_overclock() {
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        case "$PLATFORM" in
            "A30")
                /mnt/SDCARD/miyoo/utils/utils "performance" 4 1512 384 1080 1
                ;;
            "Brick"|"Flip"|"SmartPro")
                echo performance >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
                echo 2000000 >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
                ;;
        esac
        chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
        chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        log_message "CPU Mode now locked to OVERCLOCK" -v
        flag_remove "setting_cpu"
    fi
}

CFG_FILE="/mnt/SDCARD/spruce/settings/spruce.cfg"
SIMPLE_CFG_FILE="/mnt/SDCARD/spruce/settings/simple_mode.cfg"

# For simple settings that use 0/1 putting this in an if statement is the easiest usage
# For complex values, you can use setting_get and then use the value in your script by capturing it
# For example:
#    VALUE=$(setting_get "my_setting")
#    if [ "$VALUE" = "complex value" ]; then
#        do complex tasks
#    fi
#
# If simple_mode.lock exists, this function will look to simple_mode.cfg to see if the setting is defined, before looking for that setting in the standard spruce.cfg
setting_get() {
    [ $# -eq 1 ] || return 1

    if flag_check "simple_mode" && grep -q "$1" "$SIMPLE_CFG_FILE"; then
        CFG="$SIMPLE_CFG_FILE"
    else
        CFG="$CFG_FILE"
    fi

    value=$(grep "^$1=" "$CFG" | cut -d'=' -f2)
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
    case "$PLATFORM" in
        "A30")
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
            ;;
        "Flip") # todo: figure out how to make lengths equal across intensity
            if [ -z "$intensity" ]; then
                intensity="$(setting_get "rumble_intensity")"
            fi

            if [ "$intensity" = "Strong" ]; then
                timer=0
                echo -n 1 > /sys/class/gpio/gpio20/value
                while [ $timer -lt $duration ]; do
                    sleep 0.002
                    timer=$(($timer + 2))
                done &
                echo -n 0 > /sys/class/gpio/gpio20/value
            elif [ "$intensity" = "Medium" ]; then
                timer=0
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/gpio20/value
                    sleep 0.005
                    echo -n 0 > /sys/class/gpio/gpio20/value
                    sleep 0.001
                    timer=$(($timer + 6))
                done &
            elif [ "$intensity" = "Weak" ]; then
                timer=0
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/gpio20/value
                    sleep 0.003
                    echo -n 0 > /sys/class/gpio/gpio20/value
                    sleep 0.001
                    timer=$(($timer + 4))
                done &
            fi
            ;;
        "Brick" | "SmartPro") # todo: properly implement duration timer
            timer=0
            while [ $timer -lt $duration ]; do
                echo -n 1 > /sys/class/gpio/gpio227/value
                sleep 0.006
                echo -n 0 > /sys/class/gpio/gpio227/value
                timer=$(($timer + 6))
            done &
            ;;
    esac
}

# Takes a screenshot and saves it to the specified path
# Usage: take_screenshot [output_path] [game_name]
# If no output_path is provided, saves to /mnt/SDCARD/Saves/screenshots/
# If game_name is provided, it will be used as the filename (without extension)
take_screenshot() {
    local output_path="${1:-/mnt/SDCARD/Saves/screenshots}"
    local game_name="$2"
    local screenshot_path

    # Ensure the screenshots directory exists
    mkdir -p "$output_path"

    # If game name provided, use it for filename
    if [ -n "$game_name" ]; then
        screenshot_path="$output_path/${game_name}.png"
    else
        # Generate timestamp-based filename if no game name
        local timestamp=$(date +%Y%m%d_%H%M%S)
        screenshot_path="$output_path/screenshot_${timestamp}.png"
    fi

    # Copy framebuffer to temp file
    cp /dev/fb0 /tmp/fb0
    vibrate 50
    # Convert and compress framebuffer to PNG in background
    # -a: auto detection of framebuffer device
    # -f: source file
    # -w: width
    # -h: height
    # -b: bits per pixel
    # -l: line length in pixels
    [ "$PLATFORM" = "A30" ] && WIDTH=$DISPLAY_HEIGHT HEIGHT=$DISPLAY_WIDTH || WIDTH=$DISPLAY_WIDTH HEIGHT=$DISPLAY_HEIGHT # handle A30 rotation
    $BIN_PATH/fbgrab -a -f "/tmp/fb0" -w $WIDTH -h $HEIGHT -b 32 -l $WIDTH "$screenshot_path" 2>/dev/null &

    log_message "Screenshot saved to: $screenshot_path" -v
}
