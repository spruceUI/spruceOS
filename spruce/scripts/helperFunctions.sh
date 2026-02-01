#!/bin/sh

# TODO: add updated table of contents/function summaries here

# This is a collection of functions that are used in multiple scripts
# Please do not add any dependencies here, this file is meant to be self-contained
# Keep methods in alphabetical order

# Gain access to the helper variables by adding this to the top of your script:
# . /mnt/SDCARD/spruce/scripts/helperFunctions.sh

######################################################################################
# !!! DO NOT USE EXECUTE ANYTHING DIRECTLY INSIDE THIS SCRIPT, INCLUDING LOGGING !!! #
######################################################################################

# variables used in multiple different helperFunctions:
export FLAGS_DIR="/mnt/SDCARD/spruce/flags"
export MESSAGES_FILE="/var/log/messages"
POWER_OFF_SCRIPT="/mnt/SDCARD/spruce/scripts/save_poweroff.sh"

# Export for enabling SSL support in CURL
export SSL_CERT_FILE=/mnt/SDCARD/spruce/etc/ca-certificates.crt

# Detect device and export to any script sourcing helperFunctions
INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
    *"sun8i"*) export PLATFORM="A30" ;;
    *"TG5040"*)	export PLATFORM="SmartPro" ;;
    *"TG3040"*)	export PLATFORM="Brick"	;;
    *"TG5050"*)	export PLATFORM="SmartProS"	;;
    *"0xd05"*) export PLATFORM="Flip" ;;
    *"0xd04"*) export PLATFORM="Pixel2" ;;
    *) export PLATFORM="MiyooMini" ;;
esac

. /mnt/SDCARD/spruce/scripts/platform/$PLATFORM.cfg
. /mnt/SDCARD/spruce/scripts/device_functions.sh

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


restart_wifi() {
    # Requires PLATFORM and WPA_SUPPLICANT_FILE to be set
    log_message "Restarting Wi-Fi interface wlan0"

    # Bring the interface down and kill any running services
    ifconfig wlan0 down
    killall wpa_supplicant 2>/dev/null
    killall udhcpc 2>/dev/null

    # Bring the interface back up and reconnect
    ifconfig wlan0 up
    wpa_supplicant -B -i wlan0 -c "$WPA_SUPPLICANT_FILE"
    udhcpc -i wlan0 &
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

        restart_wifi
		
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

confirm() {
    timeout=${1:-0}         # Default to 0 (no timeout)
    timeout_return=${2:-1}  # Default to 1 (usually 'No' or 'Cancel')
    start_time=$(date +%s)

    rm -f /tmp/ge_out 2>/dev/null
    
    # Start getevent in the background
    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" > /tmp/ge_out &
    GE_PID=$!

    RET_VAL=2
    while [ "$RET_VAL" -eq 2 ]; do
        # 1. Check for User Input
        if line=$(tail -n 1 /tmp/ge_out 2>/dev/null); then
            case "$line" in
                *"key $B_A"*) 
                    RET_VAL=0 
                    echo "CONFIRM CONFIRMED $(date +%s)" >>"$MESSAGES_FILE"
                ;;
                *"key $B_B"*) 
                    RET_VAL=1 
                    echo "CONFIRM CANCELLED $(date +%s)" >>"$MESSAGES_FILE"
                ;;
            esac
        fi

        # 2. Check for Timeout (only if timeout > 0)
        if [ "$timeout" -gt 0 ]; then
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            if [ "$elapsed" -ge "$timeout" ]; then
                echo "CONFIRM TIMEOUT $(date +%s)" >>"$MESSAGES_FILE"
                RET_VAL=$timeout_return
            fi
        fi
        
        # 3. Prevent CPU pegging
        [ "$RET_VAL" -eq 2 ] && sleep 0.1
    done

    kill "$GE_PID" 2>/dev/null
    display_kill
    return "$RET_VAL"
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

finish_unpacking() {
    flag="$1"
    if flag_check "$flag"; then
        start_pyui_message_writer
        log_and_display_message "Finishing up unpacking archives.........."
        flag_remove "silentUnpacker"
        while [ -f "$FLAGS_DIR/$flag.lock" ]; do
            : # null operation (no sleep needed)
        done
        stop_pyui_message_writer
    fi
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


get_event() {
    "/mnt/SDCARD/spruce/bin/getevent" $EVENT_PATH_READ_INPUTS_SPRUCE
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
    verbose_flag="${2:-}"
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

low_battery_check() {
    if flag_check "low_battery"; then
        CAPACITY=$(cat $BATTERY/capacity)
        start_pyui_message_writer
        log_and_display_message "Battery has $CAPACITY% left. Charge or shutdown your device."
        sleep 1
        acknowledge
        flag_remove "low_battery"
        stop_pyui_message_writer
    fi
}

# Generate a QR code
# Usage: qr_code -t "text" -s "size" -l "level" -o "output"
# If no output is provided, the QR code will be saved to /tmp/tmp/qr.png
#   QR_CODE=$(qr_code -t "https://www.google.com")
#   display -i "$QR_CODE" -t "DT: QR Code" -d 5
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

    # Generate QR code
    if qrencode -o "$output" -s "$size" -l "$level" -m 2 "$text" >/dev/null 2>&1; then
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
    MNT_LINE=$(mount | grep -m1 $SD_DEV)
    if [ -n "$MNT_LINE" ]; then
        log_message "mount line for SD card: $MNT_LINE"
        MNT_STATUS=$(echo "$MNT_LINE" | cut -d'(' -f2 | cut -d',' -f1)
        if [ "$MNT_STATUS" = "ro" ]; then
            log_message "SD card is mounted as RO. Attempting to remount."
            mount -o remount,rw "$SD_DEV" "$SD_MOUNTPOINT"
            return 0
        else
            log_message "SD card is not read-only."
            return 1
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
        vibrate 200 &
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

        vibrate &
        sleep 0.1
        vibrate &
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
##########     PYUI MESSAGE WRITER     ##########

start_pyui_message_writer() {
    # $1 = 0 to not wait, anything else to wait
    wait_for_listener="$1"

    ifconfig lo up
    ifconfig lo 127.0.0.1

    # Check if PyUI is already running with the realtime port argument
    if pgrep -f "sgDisplayRealtimePort" >/dev/null; then
        log_message "Real Time message listener already running."
        return
    fi
    
    rm -f /mnt/SDCARD/App/PyUI/realtime_message_network_listener.txt
    log_message "Starting Real Time message listener on port 50980"
    /mnt/SDCARD/App/PyUI/launch.sh -msgDisplayRealtimePort 50980 &

    # Optional wait for the listener file
    if [ "$wait_for_listener" != "0" ]; then
        log_message "Waiting for realtime_message_network_listener to appear..."
        while [ ! -e "/mnt/SDCARD/App/PyUI/realtime_message_network_listener.txt" ]; do
            sleep 0.1
        done
        log_message "Realtime message network listener detected."
    fi
}


kill_pyui_message_writer() {

    # Check if PyUI is already running with the realtime port argument
    pids=$(pgrep -f "sgDisplayRealtimePort" | awk '{print $1}')

    if [ -n "$pids" ]; then
        log_message "Real Time message listener is running. Killing it..."
        display_message "$(printf '{"cmd":"EXIT_APP","args":[]}')"
        sleep 0.5

        # Kill all matching PIDs
        for pid in $pids; do
            kill "$pid" 2>/dev/null
        done
        # Optionally wait for processes to exit
        sleep 1
    fi    

}

stop_pyui_message_writer() {
    kill_pyui_message_writer
    freemma &>/dev/null # I don't think we have this bin on any spruce devices
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
    display_message "$(printf '{"cmd":"MESSAGE","args":["%s"]}' "$1")"
}

display_option_list(){
    log_message "Display option list $1"
    display_message "$(printf '{"cmd":"OPTION_LIST","args":["%s"]}' "$1")"
}

display_text_with_percentage_bar(){
    # $1 = Text e.g. "Hello"
    # $2 = The percentage complete e.g. 75
    # $3 = Optional bottom text
    log_message "Display text with percentage bar $1 $2"
    if [ $# -eq 2 ]; then
        display_message "$(printf '{"cmd":"TEXT_WITH_PERCENTAGE_BAR","args":["%s","%s"]}' "$1" "$2")"
    else
        display_message "$(printf '{"cmd":"TEXT_WITH_PERCENTAGE_BAR","args":["%s","%s","%s"]}' "$1" "$2" "$3")"
    fi
}

get_remote_filesize_bytes() {
    url="$1"
    wget --spider --server-response --no-check-certificate "$url" 2>&1 | grep -i 'Content-Length' | tail -n1 | awk '{print $2}' | tr -d '\r\n'
}

download_and_display_progress() {
	BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"
    remote_url="$1"
    local_path="$2"
    display_name="$3"
    final_size_bytes="$4"

    if [ -z "$final_size_bytes" ]; then
        final_size_bytes="$(get_remote_filesize_bytes "$remote_url")"
    fi

	{
		sleep 0.1
		while ps | grep '[w]get' >/dev/null; do
			current_size=$(ls -ln "$local_path" 2>/dev/null | awk '{print $5}')
			[ -z "$current_size" ] && current_size=0
			[ -z "$final_size_bytes" ] && final_size_bytes=1
			percent_complete="$(((current_size * 100) / final_size_bytes))"
			[ "$percent_complete" -gt 100 ] && percent_complete=100
            current_mb="$((current_size / 1024 / 1024))"
            final_mb="$((final_size_bytes / 1024 / 1024))"
			display_text_with_percentage_bar "Now downloading $display_name!" "$percent_complete" "$current_mb MB / $final_mb MB"
			sleep 0.1
		done 
	} &
	if ! wget --quiet --no-check-certificate --output-document="$local_path" "$remote_url"; then
		display_image_and_text "$BAD_IMG" 35 25 "Unable to download $display_name. Please try again later." 75
		sleep 4
		rm -f "$local_path" 2>/dev/null
		return 1
    else
        return 0
	fi
}

display_image_and_text() {
    # Full form (5 args):
    # $1 = image path
    # $2 = image size (%)
    # $3 = image vertical offset (%)
    # $4 = text
    # $5 = text height (%)

    # Abridged form (only 2 args):
    # $1 = image path
    # $2 = text

    if [ $# -eq 2 ]; then
        img="$1"
        text="$2"
        size="35"
        img_y="25"
        text_y="75"
    else
        img="$1"
        size="${2:-25}"
        img_y="${3:-25}"
        text="$4"
        text_y="${5:-75}"
    fi

    log_message "Display image and text $img $size $img_y $text $text_y"

    display_message "$(printf \
        '{"cmd":"IMAGE_AND_TEXT","args":["%s","%s","%s","%s","%s"]}' \
        "$img" "$text" "$size" "$img_y" "$text_y"
    )"
}

get_config_value() {
    local key="$1"
    local default="$2"
    local file="/mnt/SDCARD/Saves/spruce/spruce-config.json"

    jq -r "${key} // \"$default\"" "$file"
}

get_pyui_config_value() {
    local key="$1"
    local default="$2"

    jq -r "${key} // \"$default\"" "$SYSTEM_JSON"
}

map_color_name_to_hex() {
    name="$1"
    case "$name" in
        "Red")    hex=FF0000 ;;
        "Pink")   hex=FF3333 ;;
        "Purple") hex=FF00FF ;;
        "Blue")   hex=0000FF ;;
        "Cyan")   hex=00FFFF ;;
        "Green")  hex=00FF00 ;;
        "Yellow") hex=FFFF00 ;;
        "Orange") hex=FF5500 ;;
        *)        hex=FFFFFF ;;
    esac
    echo "$hex"
}

set_rgb_in_menu() {
    # get relevant variables from spruce-config.json
    color_name="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDcolor.selected' "Green")"
    effect="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDeffect.selected' "static")"
    duration="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDduration.selected' "1000")"

    # map color names to hex values
    color_hex="$(map_color_name_to_hex "$color_name")"

    rgb_led "lrm12" "$effect" "$color_hex" "$duration" "-1"

}

set_network_proxy() {
    enable_proxy="$(get_config_value '.menuOptions."Proxy Settings".enableProxy.selected' "False")"
    proxy_protocol="$(get_config_value '.menuOptions."Proxy Settings".proxyProtocol.selected' "http")"
    proxy_address="$(get_config_value '.menuOptions."Proxy Settings".proxyAddress.selected' "")"
    proxy_port="$(get_config_value '.menuOptions."Proxy Settings".proxyPort.selected' "")"

    proxy=""

    if [ "$enable_proxy" = "True" ]; then
        if [ -n "$proxy_address" ] && [ -n "$proxy_port" ]; then
            case "$proxy_port" in
                *[!0-9]*)
                    log_message "Invalid proxy port (not a number): $proxy_port"
                    unset http_proxy https_proxy
                    return 1
                    ;;
            esac

            if [ "$proxy_port" -lt 1 ] || [ "$proxy_port" -gt 65535 ]; then
                log_message "Invalid proxy port (out of range 1-65535): $proxy_port"
                unset http_proxy https_proxy
                return 1
            fi

            proxy="${proxy_protocol}://${proxy_address}:${proxy_port}"
        fi
    fi

    if [ -n "$proxy" ]; then
        log_message "Set network proxy as $proxy"
        export http_proxy="$proxy"
        export https_proxy="$proxy"
    else
        unset http_proxy https_proxy
    fi
}

extract_7z_with_progress() {
    UPDATE_FILE="$1"
    DEST_DIR="$2"
    LOG_LOCATION="$3" # Only logs errors

    if [ -z "$UPDATE_FILE" ] || [ -z "$DEST_DIR" ] || [ -z "$LOG_LOCATION" ]; then
        echo "Usage: extract_7z_with_progress <archive.7z> <destination> <log_file> <logo_image>"
        return 1
    fi

    LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"

    TOTAL_FILES=$(7zr l -scsUTF-8 "$UPDATE_FILE" |
        awk '$1 ~ /^[0-9][0-9][0-9][0-9]-/ { count++ } END { print count }')

    [ "$TOTAL_FILES" -eq 0 ] && TOTAL_FILES=1

    FILE_COUNT=0
    PERCENT_COMPLETE=0
    THROTTLE=10  # update UI every N files

    # Ensure destination exists
    if ! mkdir -p "$DEST_DIR"; then
        echo "Failed to create destination directory: $DEST_DIR" >>"$LOG_LOCATION"
        return 1
    fi

    7zr x -y -scsUTF-8 -bb1 -o"$DEST_DIR" "$UPDATE_FILE" 2>>"$LOG_LOCATION" |
    while read -r line || [ -n "$line" ]; do
        FILE=$(echo "$line" | sed 's/^[-[:space:]]*//')
        [ -z "$FILE" ] && continue

        FILE_COUNT=$((FILE_COUNT + 1))
        PERCENT_COMPLETE=$((FILE_COUNT * 100 / TOTAL_FILES))

        if [ $((FILE_COUNT % THROTTLE)) -eq 0 ] || [ "$FILE_COUNT" -eq "$TOTAL_FILES" ]; then
            display_text_with_percentage_bar \
                "$FILE" \
                "$PERCENT_COMPLETE" \
                "$FILE_COUNT / $TOTAL_FILES files"
        fi
    done

    RET=$?

    if [ "$RET" -ne 0 ]; then
        log_update_message "Warning: Some files may have been skipped during extraction. Check $LOG_LOCATION for details."
        display_image_and_text "$LOGO" 35 25 \
            "Extraction completed with warnings. Check the log for details." 75
    else
        log_update_message "Extraction process completed successfully"
        display_image_and_text "$LOGO" 35 25 "Extraction completed!" 75
    fi

    return "$RET"
}

enable_or_disable_wifi() {
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
        ifconfig wlan0 down         2>/dev/null
        rm -f /tmp/wifion           2>/dev/null
        touch /tmp/wifioff          2>/dev/null
        killall -9 wpa_supplicant   2>/dev/null
        killall -9 udhcpc           2>/dev/null
        log_message "WiFi turned off"

        device_wifi_power_off

    else
    
        device_wifi_power_on

        rm -f /tmp/wifioff          2>/dev/null
        touch /tmp/wifion           2>/dev/null
        ifconfig wlan0 up           2>/dev/null

        # check if WPA supplicant needs to be started or restarted
        WPA_PID=$(pgrep -f "wpa_supplicant.*wlan0")
        if [ -n "$WPA_PID" ]; then
            WPA_CMDLINE=$(tr '\0' ' ' < /proc/$WPA_PID/cmdline)
            if ! echo "$WPA_CMDLINE" | grep -q -- "-c $WPA_SUPPLICANT_FILE"; then
                log_message "wpa_supplicant using wrong config; restarting with $WPA_SUPPLICANT_FILE"
                kill -9 "$WPA_PID" 2>/dev/null
                sleep 1
                wpa_supplicant -B -D nl80211 -i wlan0 -c "$WPA_SUPPLICANT_FILE"
            fi
        else    # wpa_supplicant was not running at all, so start it
            wpa_supplicant -B -D nl80211 -i wlan0 -c "$WPA_SUPPLICANT_FILE"
        fi
        pgrep -f "udhcpc.*wlan0" >/dev/null || udhcpc -i wlan0 -b -t 5 -T 3
        /mnt/SDCARD/spruce/scripts/networkservices.sh &
        log_message "WiFi turned on"
    fi
}

get_current_app() {
    if [ -f /tmp/cmd_to_run.sh ]; then
        sed 's/[[:space:]]*$//' /tmp/cmd_to_run.sh
    else
        printf 'PyUI\n'
    fi
}

extract_entry_name() {
    cmd="$1"

    case "$cmd" in
        *emu/standard_launch.sh*)
            # Get last quoted argument
            last_arg=$(printf '%s\n' "$cmd" \
                | sed -n 's/.*"\([^"]*\)"/\1/p' \
                | tail -n 1)
            # Extract everything after the last "Roms/"
            if echo "$last_arg" | grep -q "Roms/"; then
                rom_path=$(printf '%s\n' "$last_arg" | sed 's/.*\(Roms\/.*\)/\1/')
                # Remove any trailing quote
                rom_path="${rom_path%\"}"
                printf '%s\n' "$rom_path"
            else
                printf '%s\n' "${last_arg##*/}"
            fi
            ;;
        *App/*)
            # Extract everything after the LAST "App/" including subfolders and file
            app_path=$(printf '%s\n' "$cmd" \
                | sed -n 's/.*\(App\/.*\)/\1/p' \
                | tail -n 1)
            # Remove any trailing quote
            app_path="${app_path%\"}"
            printf '%s\n' "$app_path"
            ;;
        *)
            printf '%s\n' "$cmd"
            ;;
    esac
}


log_activity_event() {
    app="$1"
    event="$2"

    [ -z "$app" ] && return 1
    [ -z "$event" ] && return 1

    ts="$(date +%s)"
    pid="$$"

    LOG_DIR="/mnt/SDCARD/Saves/spruce"
    LOG_FILE="$LOG_DIR/activity.jsonl"

    mkdir -p "$LOG_DIR" || return 1

    name=$(extract_entry_name "$app")

    safe_app=$(printf '%s' "$name" | sed '
        s/\\/\\\\/g
        s/"/\\"/g
        s/\t/\\t/g
        s/\r/\\r/g
        s/\n/\\n/g
    ')

    printf '{"ts":%s,"event":"%s","app":"%s","pid":%s}\n' \
        "$ts" "$event" "$safe_app" "$pid" >> "$LOG_FILE"
}

