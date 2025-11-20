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
# vibrate: Vibrates the device for a specified duration

# This is a collection of functions that are used in multiple scripts
# Please do not add any dependencies here, this file is meant to be self-contained
# Keep methods in alphabetical order

# Gain access to the helper variables by adding this to the top of your script:
# . /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# !!! DO NOT USE EXECUTE ANYTHING DIRECTLY INSIDE THIS SCRIPT, INCLUDING LOGGING !!!


# variables used in multiple different helperFunctions:
export FLAGS_DIR="/mnt/SDCARD/spruce/flags"
export MESSAGES_FILE="/var/log/messages"

# Export for enabling SSL support in CURL
export SSL_CERT_FILE=/mnt/SDCARD/spruce/etc/ca-certificates.crt

# Detect device and export to any script sourcing helperFunctions
INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
    *"sun8i"*) export PLATFORM="A30" ;;
    *"TG5040"*)	export PLATFORM="SmartPro" ;;
    *"TG3040"*)	export PLATFORM="Brick"	;;
    *"0xd05"*) export PLATFORM="Flip" ;;
    *) export PLATFORM="A30" ;;
esac

. /mnt/SDCARD/spruce/settings/platform/$PLATFORM.cfg

[ "$PLATFORM" = "A30" ] && export PATH="/mnt/SDCARD/spruce/bin:$PATH" || \
                           export PATH="/mnt/SDCARD/spruce/bin64:$PATH"

# Call this just by having "acknowledge" in your script
# This will pause until the user presses the A, B, or Start button
acknowledge() {
    # These echoes are needed to seperate the events in the key press log file
    echo "ACKNOWLEDGE $(date +%s)" >> "$MESSAGES_FILE"

    while true; do
        inotifywait "$MESSAGES_FILE"
        last_line=$(tail -n 1 "$MESSAGES_FILE")
        case "$last_line" in
        *"key $B_START_2"* | *"key $B_A"* | *"key $B_B"*)
            echo "ACKNOWLEDGED $(date +%s)" >>"$MESSAGES_FILE"
            log_message "last_line: $last_line" -v
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

    timeout=60  # Think about making this configurable
    start_time=$(date +%s)

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
        if [ "$PLATFORM" = "Flip" ]; then
            ifconfig wlan0 down
            killall wpa_supplicant
            killall udhcpc

            # Restart the interface and try to connect
            ifconfig wlan0 up
            wpa_supplicant -B -i wlan0 -c $WPA_SUPPLICANT_FILE
            udhcpc -i wlan0 &
        else
            log_message "Letting stock OS restart wifi for the FLIP"
        fi
		
        display --icon "/mnt/SDCARD/spruce/imgs/signal.png" -t "Waiting to connect....
Press START to continue anyway."
        {
            while true; do
                # Check for timeout
                current_time=$(date +%s)
                if [ $((current_time - start_time)) -ge $timeout ]; then
                    echo "WiFi connection timed out" >> "$MESSAGES_FILE"
                    break
                fi

                if ifconfig wlan0 | grep -qE "inet |inet6 " && ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
                    echo "Successfully connected to WiFi" >> "$MESSAGES_FILE"
                    break
                fi
                sleep 0.5
            done
        } &
        while true; do
            inotifywait "$MESSAGES_FILE"
            last_line=$(tail -n 1 "$MESSAGES_FILE")
            case $last_line in
                *"$B_START"* | *"$B_START_2"*)
                    log_message "WiFi connection cancelled by user"
                    display  --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -d 2 -t "Proceeding before connected to wifi."
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
    timeout=${1:-0}        # Default to 0 (no timeout) if not provided
    timeout_return=${2:-1} # Default to 1 if not provided
    start_time=$(date +%s)

    echo "CONFIRM $(date +%s)" >>"$MESSAGES_FILE"

    while true; do
        # Check for timeout first
        if [ "$timeout" -ne 0 ]; then
            current_time=$(date +%s)
            elapsed_time=$((current_time - start_time))
            if [ $elapsed_time -ge $timeout ]; then
                display_kill
                echo "CONFIRM TIMEOUT $(date +%s)" >>"$MESSAGES_FILE"
                return $timeout_return
            fi
        fi

        # Wait for log message update (with a shorter timeout to allow frequent timeout checks)
        if ! inotifywait -t 1 "$MESSAGES_FILE" >/dev/null 2>&1; then
            continue
        fi

        # Get the last line of log file
        last_line=$(tail -n 1 "$MESSAGES_FILE")
        case "$last_line" in
        # B button - cancel
        *"$B_B"*)
            display_kill
            echo "CONFIRM CANCELLED $(date +%s)" >>"$MESSAGES_FILE"
            return 1
            ;;
        # A button - confirm
        *"$B_A"*)
            display_kill
            echo "CONFIRM CONFIRMED $(date +%s)" >>"$MESSAGES_FILE"
            return 0
            ;;
        esac
    done
}

# Call this to set the number of CPU cores to be online
# Usage: cores_online [number of cores]
# Default is 4 cores (all cores online)
cores_online() {
    min_cores=4                # Minimum number of cores to keep online
    num_cores=${1:-$min_cores} # Default to min_cores if no argument is provided

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
    start_brightness="$SYSTEM_BRIGHTNESS_4"
    end_brightness="$SYSTEM_BRIGHTNESS_0"
    delay=0.01 # 50ms delay between each step

    # Check if another dim_screen is running
    if pgrep -f "dim_screen" | grep -v $$ >/dev/null; then
        log_message "Another dim_screen process is already running" -v
        return 1
    fi

    # Get current brightness
    current_brightness=$(cat "$DEVICE_BRIGHTNESS_PATH")

    # Check if we're already at target brightness
    if [ "$current_brightness" -le "$end_brightness" ]; then
        log_message "Screen already at target brightness" -v
        return 0
    fi

    current=$start_brightness

    while [ "$current" -gt "$end_brightness" ]; do
        echo "$current" > "$DEVICE_BRIGHTNESS_PATH"
        current=$((current - 1))
        sleep "$delay"
    done
}

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
    [ "$PLATFORM" = "SmartPro" ] && DEFAULT_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayTextWidescreen.png" || DEFAULT_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayText.png"
    ACKNOWLEDGE_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayAcknowledge.png"
    CONFIRM_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayConfirm.png"
    DEFAULT_FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"

    if [ "$PLATFORM" = "Brick" ]; then
        width=960
        LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
        DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin64/display_text.elf"

    elif [ "$PLATFORM" = "SmartPro" ]; then
        width=1200
        LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
        DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin64/display_text.elf"

    elif [ "$PLATFORM" = "Flip" ]; then
        width=600
        DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin64/display_text.elf"

    elif [ "$PLATFORM" = "A30" ]; then
        DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin/display_text.elf"
        width=600
    fi

    image="$DEFAULT_IMAGE" text=" " delay=0 size=30 position=50 align="middle" color="ebdbb2" font=""
    use_acknowledge_image=false
    use_confirm_image=false
    run_acknowledge=false
    bg_color="7f7f7f" bg_alpha=0 image_scaling=1.0
    icon_image=""
    additional_images=""
    position_set=false
    qr_url=""

    while [ $# -gt 0 ]; do
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
                if [ "$position_set" = false ]; then
                    position=80
                fi
                shift
                ;;
            --add-image)
                additional_images="$additional_images \"$2\" $3 $4 $5"
                shift 4
                ;;
            --qr)
                qr_url="$2"
                if [ "$position_set" = false ]; then
                    position=89
                fi
                shift
                ;;
            *) log_message "Unknown option: $1"; return 1 ;;
        esac
        shift
    done
    r=$(echo "$color" | cut -c1-2)
    g=$(echo "$color" | cut -c3-4)
    b=$(echo "$color" | cut -c5-6)
    bg_r=$(echo "$bg_color" | cut -c1-2)
    bg_g=$(echo "$bg_color" | cut -c3-4)
    bg_b=$(echo "$bg_color" | cut -c5-6)

    # Set font to DEFAULT_FONT if it's empty
    if [ -z "$font" ]; then
        font="$DEFAULT_FONT"
    fi

    command="LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\" $DISPLAY_TEXT_FILE "
    command="$command""$DISPLAY_WIDTH $DISPLAY_HEIGHT $DISPLAY_ROTATION "

    # Construct the command
    command="$command""\"$image\" \"$text\" $delay $size $position $align $width $r $g $b \"$font\" $bg_r $bg_g $bg_b $bg_alpha $image_scaling"

    # Add icon image if specified
    if [ -n "$icon_image" ]; then
        command="$command \"$icon_image\" 0.20 center middle"
    fi

    # Add CONFIRM_IMAGE if --confirm flag is used, otherwise use ACKNOWLEDGE_IMAGE if --okay flag is used
    if [ "$use_confirm_image" = true ]; then
        command="$command \"$CONFIRM_IMAGE\" 1.0 240 middle"
        delay=0
    elif [ "$use_acknowledge_image" = true ]; then
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
            command="$command \"$qr_image\" 0.50 top middle"
        else
            log_message "Failed to generate QR code for URL: $qr_url" -v
        fi
    fi

    display_kill

    # Execute the command in the background if delay is 0
    if [ "$delay" -eq 0 ]; then
        eval "$command" &
        log_message "display command: $command"
        # Run acknowledge if -o or --okay was used and --confirm was not used
        if [ "$run_acknowledge" = true ] && [ "$use_confirm_image" = false ]; then
            acknowledge
        fi
    else
        # Execute the command and capture its output
        eval "$command"
        log_message "display command: $command"
    fi
}

# Call this to kill any display processes left running
# If you use display() at all you need to call this on all the possible exits of your script
display_kill() {
    kill -9 $(pgrep display) 2> /dev/null
}

# used in principal.sh
enable_or_disable_rgb() {
    case "$PLATFORM" in
        "Brick"|"SmartPro")
            enable_file="/sys/class/led_anim/enable"
        	disable_rgb="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
            if [ "$disable_rgb" = "True" ]; then
                chmod 777 "$enable_file" 2>/dev/null
                echo 0 > "$enable_file" 2>/dev/null
                chmod 000 "$enable_file" 2>/dev/null
            else
                chmod 777 "$enable_file" 2>/dev/null
                echo 1 > "$enable_file" 2>/dev/null
                # don't lock them back afterwards
            fi
            ;;
        *)
            ;;
    esac
}

# Add a flag
# Usage: flag_add "flag_name"
flag_add() {
    local flag_name="$1"
    touch "$FLAGS_DIR/${flag_name}.lock"
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
    button_pressed=""
    timeout=${1:-180}  # Default 180 second timeout if not specified
    start_time=$(date +%s)

    echo "GET_BUTTON_PRESS $(date +%s)" >>"$MESSAGES_FILE"

    while true; do
        # Check for timeout
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ $elapsed_time -ge $timeout ]; then
            echo "GET_BUTTON_PRESS TIMEOUT $(date +%s)" >>"$MESSAGES_FILE"
            echo "B"
            return 1
        fi

        # Wait for log message update
        if ! inotifywait -t 1 "$MESSAGES_FILE" >/dev/null 2>&1; then
            continue
        fi

        # Get the last line of log file
        last_line=$(tail -n 1 "$MESSAGES_FILE")
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
            echo "GET_BUTTON_PRESS RECEIVED $button_pressed $(date +%s)" >>"$MESSAGES_FILE"
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
        log_message "Error: Configuration file not found at $SYSTEM_JSON"
        return 1
    fi

    # Extract "theme" from JSON, ignoring errors
    theme_name=$(jq -r '.theme' "$SYSTEM_JSON")

    # If "theme" is empty
    if [ -z "$theme_name" ]; then
        log_message "Error: Could not retrieve theme name from $SYSTEM_JSON"
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
    theme_path=$(get_current_theme_path)
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
    current_theme_path=$(get_current_theme_path)
    spruce_theme="/mnt/SDCARD/Themes/SPRUCE/"
    default_theme="../res/"
    default_theme_2="./"

    # if the current theme is equal to the default miyoo theme
    if [ "$current_theme_path" = "$default_theme" ]; then # that's ugly!
        echo "$spruce_theme"                                 # Switch to the spruce theme ASAP
    elif [ "$current_theme_path" = "$default_theme_2" ]; then # that's ugly!
        echo "$spruce_theme"                                     # Switch to the spruce theme ASAP
    else # If not, give back the user his loved theme <3
        echo "$current_theme_path"
    fi
}


get_event() {
    "/mnt/SDCARD/spruce/bin/getevent" $EVENT_PATH_KEYBOARD
}

get_version() {
    spruce_file="/mnt/SDCARD/spruce/spruce"

    if [ ! -f "$spruce_file" ]; then
        echo "0"
        return 1
    fi

    version=$(cat "$spruce_file" | tr -d '[:space:]')

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
    base_version=$(get_version)

    # Ensure we got a valid base version
    if [ -z "$base_version" ] || [ "$base_version" = "0" ]; then
        echo "$base_version"
        return 1
    fi

    version_pattern="/mnt/SDCARD/${base_version}-*"
    
    # Find any matching version file (beta or nightly)
    test_file=$(ls $version_pattern 2>/dev/null | head -n 1)

    if [ -n "$test_file" ]; then
        test_version=$(basename "$test_file")
        echo "$test_version"
    else
        echo "$base_version"
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
    message="$1"
    verbose_flag="$2"
    custom_log_file="${3:-$log_file}"

    # Check if it's a verbose message and if verbose logging is not enabled
    [ "$verbose_flag" = "-v" ] && ! flag_check "log_verbose" && return

    # Handle custom log file
    if [ "$custom_log_file" != "$log_file" ]; then
        mkdir -p "$(dirname "$custom_log_file")"
        touch "$custom_log_file"
    fi

    printf '%s%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${verbose_flag:+ -v}" "$message" | tee -a "$custom_log_file"
}

# Call this to toggle verbose logging
# After this is called, any log_message calls will output to the log file if -v is passed
# USE THIS ONLY WHEN DEBUGGING, IT WILL GENERATE A LOT OF LOG FILE ENTRIES
# Remove it from your script when done.
# Can be used as a toggle: calling it once enables verbose logging, calling it again disables it
log_verbose() {
    calling_script=$(basename "$0")
    if flag_check "log_verbose"; then
        flag_remove "log_verbose"
        log_message "Verbose logging disabled in script: $calling_script"
    else
        flag_add "log_verbose"
        log_message "Verbose logging enabled in script: $calling_script"
    fi
}

log_precise() {
    message="$1"
    date_part=$(date '+%Y-%m-%d %H:%M:%S')
    uptime_part=$(cut -d ' ' -f 1 /proc/uptime)
    timestamp="${date_part}.${uptime_part#*.}"
    printf '%s %s\n' "$timestamp" "$message" >>"$log_file"
}

# Generate a QR code
# Usage: qr_code -t "text" -s "size" -l "level" -o "output"
# If no output is provided, the QR code will be saved to /tmp/tmp/qr.png
#   QR_CODE=$(qr_code -t "https://www.google.com")
#   display -i "$QR_CODE" -t "DT: QR Code" -d 5
QRENCODE_PATH="/mnt/SDCARD/spruce/bin/qrencode"
QRENCODE64_PATH="/mnt/SDCARD/spruce/bin64/qrencode"
qr_code() {
    text=""
    size=3
    level="M"
    output="/mnt/SDCARD/spruce/tmp/qr.png"

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

    qr_bin_path=$QRENCODE_PATH
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
    log_message "Performing read-only check"
    SD_or_sd=$(mount | grep -q SDCARD && echo "SDCARD" || echo "sdcard")
    log_message "Device uses /mnt/$SD_or_sd for its SD card path" -v
    MNT_LINE=$(mount | grep "$SD_or_sd")
    if [ -n "$MNT_LINE" ]; then
        log_message "mount line for SD card: $MNT_LINE" -v
        MNT_STATUS=$(echo "$MNT_LINE" | cut -d'(' -f2 | cut -d',' -f1)
        if [ "$MNT_STATUS" = "ro" ] && [ -n "$SD_DEV" ]; then
            log_message "SD card is mounted as RO. Attempting to remount."
            mount -o remount,rw "$SD_DEV" /mnt/"$SD_or_sd"
        else
            log_message "SD card is not read-only."
        fi
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
        pid=$(cat "/tmp/ffmpeg_recording.pid")
        kill "$pid" 2>/dev/null
        rm "/tmp/ffmpeg_recording.pid"
        flag_remove "setting_cpu"
        log_message "Stopped recording" -v
        sleep 1
        display -t "Recording stopped" -d 3
    else
        # Start new recording
        output_file="$1"
        timeout_minutes="${2:-5}"  # Default to 5 minutes if not specified
        date_str=$(date +%Y-%m-%d_%H-%M-%S)
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

sanitize_system_json() {
    if ! jq '.' "$SYSTEM_JSON" > /dev/null 2>&1; then
        log_message "$0: Invalid System JSON detected, sanitizing..."
        jq '.' "$SYSTEM_JSON" > /tmp/system.json.clean 2>/dev/null || cp /mnt/SDCARD/spruce/settings/platform/system-${PLATFORM}.json /tmp/system.json.clean
        mv /tmp/system.json.clean "$SYSTEM_JSON"
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
        echo 45 >$CONSERVATIVE_POLICY_DIR/down_threshold
        echo 75 >$CONSERVATIVE_POLICY_DIR/up_threshold
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

##########     NEW PYUI-BASED SETTING SYSTEM     ##########

# Get spruce-specific settings from spruce-config.json
# example usage:
# SMB_ENABLED="$(get_config_value '.menuOptions."Network Settings".enableSMB.selected' "True")"
get_config_value() {
    local key="$1"
    local default="$2"
    local file="/mnt/SDCARD/Saves/spruce/spruce-config.json"

    jq -r "${key} // \"$default\"" "$file"
}

###########################################################

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
    duration=50
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

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

    case "$PLATFORM" in
        "A30")
            if [ "$intensity" = "Strong" ]; then    # 100% duty cycle
                echo "$duration" >/sys/devices/virtual/timed_output/vibrator/enable
            elif [ "$intensity" = "Medium" ]; then  # 83% duty cycle
                timer=0
                while [ $timer -lt $duration ]; do
                    echo 5 >/sys/devices/virtual/timed_output/vibrator/enable
                    sleep 0.006
                    timer=$(($timer + 6))
                done &
            elif [ "$intensity" = "Weak" ]; then    # 75% duty cycle
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
        "Flip") 
            # todo: figure out how to make lengths equal across intensity
            if [ "$intensity" = "Strong" ]; then    # 100% duty cycle
                timer=0
                echo -n 1 > /sys/class/gpio/gpio20/value
                while [ $timer -lt $duration ]; do
                    sleep 0.002
                    timer=$(($timer + 2))
                done
                echo -n 0 > /sys/class/gpio/gpio20/value
            elif [ "$intensity" = "Medium" ]; then  # 83% duty cycle
                timer=0
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/gpio20/value
                    sleep 0.005
                    echo -n 0 > /sys/class/gpio/gpio20/value
                    sleep 0.001
                    timer=$(($timer + 6))
                done &
            elif [ "$intensity" = "Weak" ]; then    # 75% duty cycle
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
        "Brick" | "SmartPro") 
            # todo: properly implement duration timer and intensity
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
    output_path="${1:-/mnt/SDCARD/Saves/screenshots}"
    game_name="$2"

    # Ensure the screenshots directory exists
    mkdir -p "$output_path"

    # If game name provided, use it for filename
    if [ -n "$game_name" ]; then
        screenshot_path="$output_path/${game_name}.png"
    else
        # Generate timestamp-based filename if no game name
        timestamp=$(date +%Y%m%d_%H%M%S)
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



##########     PYUI MESSAGE WRITER     ##########

start_pyui_message_writer() {
    # Check if PyUI is already running with the realtime port argument
    if ps -ef | grep "[m]sgDisplayRealtimePort" >/dev/null; then
        log_message "Real Time message listener already running."
        return
    fi
    
    log_message "Starting Real Time message listener on port 50980"
    /mnt/SDCARD/App/PyUI/launch.sh -msgDisplayRealtimePort 50980 &
    sleep 3
}

kill_pyui_message_writer() {

    # Check if PyUI is already running with the realtime port argument
    pids=$(ps -ef | grep "[m]sgDisplayRealtimePort" | awk '{print $1}')

    if [ -n "$pids" ]; then
        log_message "Real Time message listener already running. Killing it..."
        # Kill all matching PIDs
        for pid in $pids; do
            kill "$pid" 2>/dev/null
        done
        # Optionally wait for processes to exit
        sleep 1
    fi    

}

stop_pyui_message_writer() {
    display_message "EXIT_APP"
    sleep 0.5
    kill_pyui_message_writer
    freemma
}

get_python_path() {
    if [ "$PLATFORM" = "A30" ]; then
        echo "/mnt/SDCARD/spruce/bin/python/bin/python3.10"
    elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "Flip" ]; then
        echo "/mnt/SDCARD/spruce/flip/bin/python3.10"
    fi
}

display_message() {
    local message="$1"
    local python_path
    python_path="$(get_python_path)"

    if [ -z "$python_path" ]; then
        echo "Error: unknown platform '$PLATFORM'" >&2
        return 1
    fi

    MESSAGE="$message" "$python_path" - <<'EOF'
import os, socket, sys
msg = os.environ.get("MESSAGE", "")
try:
    with socket.create_connection(("127.0.0.1", 50980), timeout=1) as s:
        s.sendall((msg + "\n").encode("utf-8"))
except Exception as e:
    print(f"Error sending message: {e}", file=sys.stderr)
EOF
}

log_and_display_message(){
    log_message "$1"
    display_message "$1"
}

# ---------------------------------------------------------------------------
# rgb_led <zones> <effect> [color] [duration_ms] [cycles]
#
# Controls RGB LEDs on TrimUI Brick / Smart Pro.
#
# PARAMETERS:
#   <zones>        A string containing any combination of: l r m 1 2
#                  (order does not matter)
#                  Zones resolve to:
#                     l  → left LED
#                     r  → right LED
#                     m  → middle LED
#                     1  → front LED f1
#                     2  → front LED f2
#                  Example: "lrm12", "m1", "r2", "l"
#
#   <effect>       One of the following keywords or numeric equivalents:
#                     0 | off | disable      → off
#                     1 | linear | rise      → linear rise
#                     2 | breath*            → breathing pattern
#                     3 | sniff              → "sniff" animation
#                     4 | static | on        → solid color
#                     5 | blink*1            → blink pattern 1
#                     6 | blink*2            → blink pattern 2
#                     7 | blink*3            → blink pattern 3
#
#   [color]        Hex RGB color (default: "FFFFFF")
#
#   [duration_ms]  Animation duration in milliseconds (default: 1000)
#
#   [cycles]       Number of animation cycles (default: 1)
#
# EXAMPLES:
#   rgb_led lrm breathe FF8800 2000 3
#   rgb_led m2 blink1 00FFAA
#   rgb_led 12 static
#   rgb_led r off
# ---------------------------------------------------------------------------

rgb_led() {

    # early out
	disable="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
	if [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "Flip" ] || [ "$disable" = "True" ]; then
		return 0	# exit if device has no LEDs to twinkle or user opts out
	fi

    # parse led zones to affect from first argument
    if [ -n "$1" ]; then
        zones=""
        for z in l r m 1 2; do
            case "$1" in
                *"$z"*) zones="$zones $z";;
            esac
        done
    else
        zones="l r m 1 2"
    fi

    # translate 1 → f1 and 2 → f2
    new_zones=""
    for z in $zones; do
        case "$z" in
            1) new_zones="$new_zones f1" ;;
            2) new_zones="$new_zones f2" ;;
            *) new_zones="$new_zones $z" ;;
        esac
    done
    zones="$new_zones"

    # parse effect to use from second argument
    case "$2" in
        0|off|disable) effect=0 ;;
        1|linear|rise) effect=1 ;;
        2|breath*) effect=2 ;;
        3|sniff) effect=3 ;;
        4|static|on) effect=4 ;;
        5|blink*1) effect=5 ;;
        6|blink*2) effect=6 ;;
        7|blink*3) effect=7 ;;
        *) effect=4 ;;
    esac

    # get color, duration, and cycles literally from args 3,4,5, with fallbacks if missing
    color=${3:-"FFFFFF"}
    duration=${4:-1000}
    cycles=${5:-1}

    # do the things
   	echo 1 > /sys/class/led_anim/effect_enable 2>/dev/null
	for zone in $zones; do
		echo "$color" > /sys/class/led_anim/effect_rgb_hex_$zone 2>/dev/null
		echo "$cycles" > /sys/class/led_anim/effect_cycles_$zone 2>/dev/null
		echo "$duration" > /sys/class/led_anim/effect_duration_$zone 2>/dev/null
		echo "$effect" > /sys/class/led_anim/effect_$zone 2>/dev/null
	done
}

rainbreathe() {
    for color in FF0000 FF8000 FFFF00 80FF00 \
                 00FF00 00FF80 00FFFF 0080FF \
                 0000FF 8000FF FF00FF FF0080; do
        rgb_led lrm12 breathe $color ${1:-2000}
        sleep ${2:-3}
    done
}