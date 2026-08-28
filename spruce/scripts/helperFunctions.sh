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
export WPA_SUPPLICANT_FILE="/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf"
POWER_OFF_SCRIPT="/mnt/SDCARD/spruce/scripts/save_poweroff.sh"

# Export for enabling SSL support in CURL
export SSL_CERT_FILE=/mnt/SDCARD/spruce/etc/ca-certificates.crt

# Detect device and export to any script sourcing helperFunctions
INFO=$(cat /proc/cpuinfo 2> /dev/null)

case $INFO in
    *sun8i*) export PLATFORM="A30" ;;           # A33
    *TG5040*) export PLATFORM="SmartPro" ;;
    *TG3040*) export PLATFORM="Brick" ;;
    *TG5050*) export PLATFORM="SmartProS" ;;
    *TG4040*) export PLATFORM="BrickPro" ;;
    *0xd05*)                                    # RK3566
        if grep -q '^OS_NAME="DARKMOSS"' /etc/os-release 2>/dev/null; then
            # The kernel names the board in the device tree.
            DT_MODEL=$(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null)
            case "$DT_MODEL" in
                *RGB30*) export PLATFORM="RGB30" ;;
                *) export PLATFORM="RGB30" ;;
            esac
        else
            export PLATFORM="Flip"
        fi
        ;;
    *0xd04*) export PLATFORM="Pixel2" ;;        # RK3326
    *0xd03*)                                    # H700
        export SPRUCE_BASEOS=1
        BASEOS_TARGET=$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null)
        case $BASEOS_TARGET in
            rg28xx)                 export PLATFORM="AnbernicRG28XX" ;;
            rgcubexx)               export PLATFORM="AnbernicRGCubeXX" ;;
            rg34xx|rg34xxsp|rgsp)   export PLATFORM="AnbernicXX720480" ;;
            *)                      export PLATFORM="AnbernicXX640480" ;;
        esac
        ;;
    *) 
        if [ -e /usr/magicx ]; then
            export PLATFORM="Zero28"
        else
            export PLATFORM="MiyooMini" 
        fi
        ;;
esac

. /mnt/SDCARD/spruce/scripts/platform/$PLATFORM.cfg
. /mnt/SDCARD/spruce/scripts/device_functions.sh

# Call this just by having "acknowledge" in your script
# This will pause until the user presses the A, B, or Start button
acknowledge() {
    rm -f /tmp/ge_out 2>/dev/null

    # Start getevent in the background
    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" > /tmp/ge_out &
    GE_PID=$!

    while true; do
        if line=$(tail -n 1 /tmp/ge_out 2>/dev/null); then
            case "$line" in
                *"key $B_START_2"* | *"key $B_A"* | *"key $B_B"*)
                    log_message "last_line: $line" -v
                    break
                    ;;
            esac
        fi

        # Prevent CPU pegging (giggity)
        sleep 0.1
    done

    kill "$GE_PID" 2>/dev/null
    display_kill
}

auto_regen_tmp_update() {
    tmp_dir="/mnt/SDCARD/.tmp_update"
    updater="/mnt/SDCARD/spruce/scripts/.tmp_update/updater"
    if ! flag_check "tmp_update_repair_attempted"; then
        [ ! -d "$tmp_dir" ] && mkdir "$tmp_dir" && flag_add "tmp_update_repair_attempted" && log_message ".tmp_update folder repair attempted. Adding tmp_update_repair_attempted flag."
        [ ! -f "$tmp_dir/updater" ] && cp "$updater" "$tmp_dir/updater"
    fi
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
                ;;
                *"key $B_B"*) 
                    RET_VAL=1 
                ;;
            esac
        fi

        # 2. Check for Timeout (only if timeout > 0)
        if [ "$timeout" -gt 0 ]; then
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            if [ "$elapsed" -ge "$timeout" ]; then
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
    # Get current brightness
    start_brightness=$(cat "$DEVICE_BRIGHTNESS_PATH")
    end_brightness="$SYSTEM_BRIGHTNESS_0"
    delay=0.05 # 50ms delay between each step
    
    # Start at 4 if higher (so it's faster)
    if [ "$start_brightness" -gt "$SYSTEM_BRIGHTNESS_4" ]; then
        start_brightness="$SYSTEM_BRIGHTNESS_4"
    fi

    # Check if another dim_screen is running
    if pgrep -f "dim_screen" | grep -v $$ >/dev/null; then
        log_message "Another dim_screen process is already running" -v
        return 1
    fi

    # Check if we're already at target brightness
    if [ "$start_brightness" -le "$end_brightness" ]; then
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
        while [ -f "$FLAGS_DIR/$flag.lock" ]; do
            : # null operation (no sleep needed)
        done
        flag_remove "silentUnpacker"
        stop_pyui_message_writer
    fi
}

calculate_progress_percent() {
    completed="${1:-0}"
    total="${2:-0}"

    if [ "$total" -le 0 ] 2>/dev/null; then
        printf '100\n'
        return 0
    fi

    percent=$((completed * 100 / total))
    [ "$percent" -lt 0 ] && percent=0
    [ "$percent" -gt 100 ] && percent=100
    printf '%s\n' "$percent"
}

format_firstboot_extract_progress_text() {
    completed="${1:-0}"
    total="${2:-0}"
    percent="$(calculate_progress_percent "$completed" "$total")"
    printf 'Sprucing up your device...\\nExtracting files: %s%%' "$percent"
}

display_firstboot_extract_progress() {
    completed="${1:-0}"
    total="${2:-0}"
    icon="${3:-/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png}"

    start_pyui_message_writer
    display_image_and_text "$icon" 35 25 "$(format_firstboot_extract_progress_text "$completed" "$total")" 75
}

# Add a flag
# Usage: flag_add "flag_name"
# Usage 2: flag_add "flag_name" --tmp   --> creates flag in /tmp/ instead, to avoid unnecessary SD writes and stuck states
flag_add() {
    local flag_name="$1"
    local dest="$FLAGS_DIR"
    if [ "$2" = "--tmp" ]; then
        dest="/tmp"
    fi
    touch "$dest/${flag_name}.lock"
}

# Check if a flag exists
# Usage: flag_check "flag_name"
# Returns 0 if the flag exists (with or without .lock extension), 1 if it doesn't
flag_check() {
    local flag_name="$1"
    if [ -f "$FLAGS_DIR/${flag_name}" ] || [ -f "$FLAGS_DIR/${flag_name}.lock" ] || [ -f "/tmp/${flag_name}.lock" ]; then
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
    rm -f "/tmp/${flag_name}.lock"
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
        CAPACITY=$(device_get_battery_percent)
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


# returns 0 if SD is read-only or write test fails
# returns 1 if SD is writable
read_only_check() {
    log_message "Performing read-only check"
    MNT_LINE=$(mount | grep -m1 $SD_DEV)
    log_message "mount line for SD card: $MNT_LINE"

    mkdir -p /mnt/SDCARD/spruce/flags 2>/dev/null
    TEST_FILE="/mnt/SDCARD/spruce/flags/test-$(date +%s)"
    touch "$TEST_FILE"
    echo "testing!" > "$TEST_FILE"
    if [ ! -e "$TEST_FILE" ]; then
        # this log will most likely fail to write lol
        log_message "Unable to create write test file. SD card is likely mounted read-only."
        return 0
    elif ! grep -q "testing!" "$TEST_FILE"; then
        log_message "Test file created successfully but did not contain test message. SD card likely remounted as read-only."
        return 0
    else
        log_message "SD card does not appear to be read only"
        # A passing write test is authoritative: the card is writable. Return
        # that now rather than falling through to the mount-line check below.
        # That check reports read-only whenever SD_DEV is absent from the mount
        # table, because an `if` with no matching branch and no else exits 0 -
        # so on a base whose TF2 device node does not match SD_DEV, a perfectly
        # writable card is called read-only forever and repairSD loops.
        rm -f "$TEST_FILE"
        return 1
    fi
}


run_upgrade_scripts() {
    UPGRADE_SCRIPTS_DIR="/mnt/SDCARD/App/spruceRestore/UpgradeScripts"
    last_update_file="/mnt/SDCARD/App/spruceRestore/.lastUpdate"

    if [ -f "$last_update_file" ]; then
        current_version=$(grep "spruce_version=" "$last_update_file" | cut -d'=' -f2 | tr -d '\r\n')
    else
        current_version="2.0.0"
    fi

    log_message "Upgrade scripts: current version is $current_version"

    if [ ! -d "$UPGRADE_SCRIPTS_DIR" ]; then
        log_message "Upgrade scripts: directory not found, skipping"
        return 0
    fi

    is_developer_mode=$(flag_check "developer_mode" && echo "true" || echo "false")
    is_tester_mode=$(flag_check "tester_mode" && echo "true" || echo "false")
    allow_same_version=0

    if [ "$is_developer_mode" = "true" ] || [ "$is_tester_mode" = "true" ]; then
        allow_same_version=1
        log_message "Upgrade scripts: dev/tester mode detected, allowing same version upgrades"
    fi

    cd "$UPGRADE_SCRIPTS_DIR" || return 1

    for script in *.sh; do
        [ -f "$script" ] || continue

        script_version=$(echo "$script" | cut -d'.' -f1-3)

        version_compare=$(echo "$current_version $script_version" | awk '{
            split($1, a, ".")
            split($2, b, ".")
            for (i = 1; i <= 3; i++) {
                if (a[i] < b[i]) { print "older"; exit }
                else if (a[i] > b[i]) { print "newer"; exit }
            }
            print "equal"
        }')

        if [ "$version_compare" = "older" ] || ([ "$version_compare" = "equal" ] && [ $allow_same_version -eq 1 ]); then
            log_message "Upgrade scripts: running $script"
            output=$(sh "$script" 2>&1)
            exit_status=$?
            log_message "Upgrade scripts: output from $script:"
            echo "$output" >> "${log_file:-/mnt/SDCARD/Saves/spruce/spruce.log}"

            if [ $exit_status -eq 0 ]; then
                log_message "Upgrade scripts: $script completed successfully"
                echo "spruce_version=$script_version" > "$last_update_file"
                current_version=$script_version
            else
                log_message "Upgrade scripts: $script failed with exit status $exit_status"
                cd - > /dev/null
                return 1
            fi
        else
            log_message "Upgrade scripts: skipping $script (current $current_version >= $script_version)"
        fi
    done

    cd - > /dev/null
    log_message "Upgrade scripts: completed. Current version: $current_version"
    return 0
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
    [ -z "$message" ] && return 0

    # We use double quotes for the -c string so we can use single quotes inside.
    # We pass "$message" as the final argument which Python picks up as sys.argv[1]
    "$(get_python_path)" -c 'import socket, sys;
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.5)
    s.connect(b"\x0050980")
    s.sendall((sys.argv[1] + "\n").encode("utf-8"))
    s.close()
except Exception as e:
    print(f"Sender Error: {e}", file=sys.stderr)
' "$message"
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

# BaseOS ships busybox wget as /usr/bin/wget. It rejects every GNU long option
# outright - --quiet, --no-check-certificate and --max-redirect each make it
# print its usage block and exit non-zero - and even with busybox-safe flags it
# cannot finish an HTTPS transfer, because there is no ssl_helper on the system:
# it connects, prints "note: TLS certificate validation not implemented", then
# writes nothing. The GNU wget we ship in spruce/bin64 is no escape either - on
# BaseOS it will not load, for want of libpcre.so.1 and then libuuid.so.1.
#
# curl is present and working on every platform we ship, so it is the transport
# here, with busybox-safe wget kept as a fallback. Certificates are verified
# against the bundled CA file (SSL_CERT_FILE) first; only a TLS failure retries
# with -k, which preserves the --no-check-certificate behaviour these downloads
# have always had on firmware whose TLS stack cannot use the bundle.
download_url_to_file() {
    # $1 = remote url, $2 = destination path
    if command -v curl >/dev/null 2>&1; then
        # -f so an HTTP error exits non-zero and leaves no file behind, which is
        # what wget did and what every caller here assumes. curl's own message
        # goes to the log rather than to stderr, where it would paint over the
        # UI the calling app is drawing.
        curl_error="$(curl -sSL -f --connect-timeout 15 -o "$2" "$1" 2>&1)"
        curl_result=$?
        case "$curl_result" in
            35|51|58|59|60|77)
                log_message "download_url_to_file: TLS verification failed for $1 (curl $curl_result: $curl_error); retrying without certificate verification"
                curl_error="$(curl -sSLk -f --connect-timeout 15 -o "$2" "$1" 2>&1)"
                curl_result=$?
                ;;
        esac
        [ "$curl_result" -ne 0 ] && log_message "download_url_to_file: curl failed for $1 - $curl_error"
        return "$curl_result"
    else
        wget -q -O "$2" "$1"
    fi
}

get_remote_filesize_bytes() {
    url="$1"
    if command -v curl >/dev/null 2>&1; then
        # Headers only, following redirects. A GitHub release asset 302s to a
        # storage host, so several Content-Length lines come back and the last
        # one belongs to the asset itself.
        curl -sILk --connect-timeout 15 "$url" 2>/dev/null | grep -i 'Content-Length' | tail -n1 | awk '{print $2}' | tr -d '\r\n'
    else
        wget -S --spider -q -O /dev/null "$url" 2>&1 | grep -i 'Content-Length' | tail -n1 | awk '{print $2}' | tr -d '\r\n'
    fi
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

    download_url_to_file "$remote_url" "$local_path" &
    download_pid=$!

	{
		sleep 0.1
		# Watch the transfer we started rather than asking whether any wget is
		# running - that global match also caught unrelated downloads, and it
		# stopped seeing this one at all once the transport was no longer wget.
		while kill -0 "$download_pid" 2>/dev/null; do
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
	progress_pid=$!

	wait "$download_pid"
	download_result=$?
	wait "$progress_pid" 2>/dev/null

	if [ "$download_result" -ne 0 ]; then
		display_image_and_text "$BAD_IMG" 35 25 "Unable to download $display_name. Please try again later." 75
		sleep 4
		rm -f "$local_path" 2>/dev/null
        sync
		return 1
    else
        sync
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

get_pyui_config_value() {
    local key="$1"
    local default="$2"

    jq -r "${key} // \"$default\"" "$SYSTEM_JSON"
}

map_color_name_to_hex() {
    name="$1"
    case "$name" in
        "Red")          hex=FF0000 ;;
        "Pink")         hex=FF3333 ;;
        "Fuchsia")      hex=FF0022 ;;
        "Purple")       hex=FF00FF ;;
        "Dark Purple")  hex=2200CC ;;
        "Blue")         hex=0000FF ;;
        "Cyan")         hex=00FFFF ;;
        "Teal")         hex=00FF22 ;;
        "Green")        hex=00FF00 ;;
        "Yellow")       hex=FFFF00 ;;
        "Orange")       hex=FF1100 ;;
        *)              hex=FFFFFF ;;
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
    SECTION_LABEL="$4" # Optional: section title used in "Unpacking <section>"
    SUPPRESS_PROGRESS_UI="${SPRUCE_SUPPRESS_EXTRACT_PROGRESS_UI:-0}"

    if [ -z "$UPDATE_FILE" ] || [ -z "$DEST_DIR" ] || [ -z "$LOG_LOCATION" ]; then
        echo "Usage: extract_7z_with_progress <archive.7z> <destination> <log_file> [section_label]"
        return 1
    fi

    LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
    if [ -z "$SECTION_LABEL" ]; then
        SECTION_LABEL="$(basename "$UPDATE_FILE" .7z)"
    fi

    if [ "${SPRUCE_FIRSTBOOT_UI:-0}" = "1" ]; then
        SECTION_TITLE="Sprucing up your device...\nUnpacking ${SECTION_LABEL}"
    else
        SECTION_TITLE="Unpacking ${SECTION_LABEL}"
    fi

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

    if [ "$SUPPRESS_PROGRESS_UI" != "1" ]; then
        display_image_and_text "$LOGO" 35 25 "${SECTION_TITLE}\nPreparing extraction..." 75
        sleep 2
    fi

    7zr x -y -scsUTF-8 -bb1 -o"$DEST_DIR" "$UPDATE_FILE" 2>>"$LOG_LOCATION" |
    while read -r line || [ -n "$line" ]; do
        case "$line" in
            "- "*) FILE="${line#- }" ;;
            "Extracting  "*) FILE="${line#Extracting  }" ;;
            "Inflating  "*) FILE="${line#Inflating  }" ;;
            *) continue ;;
        esac
        [ -z "$FILE" ] && continue

        FILE_COUNT=$((FILE_COUNT + 1))
        PERCENT_COMPLETE=$((FILE_COUNT * 100 / TOTAL_FILES))
        [ "$PERCENT_COMPLETE" -gt 100 ] && PERCENT_COMPLETE=100

        if [ "$SUPPRESS_PROGRESS_UI" != "1" ] &&
            { [ $((FILE_COUNT % THROTTLE)) -eq 0 ] || [ "$FILE_COUNT" -eq "$TOTAL_FILES" ]; }; then
            FILE_NAME="$(basename "$FILE")"
            display_image_and_text \
                "$LOGO" \
                35 25 \
                "${SECTION_TITLE}\n${PERCENT_COMPLETE}%: ${FILE_NAME}" \
                75
        fi
    done

    RET=$?

    if [ "$RET" -ne 0 ]; then
        log_update_message "Warning: Some files may have been skipped during extraction. Check $LOG_LOCATION for details."
        if [ "$SUPPRESS_PROGRESS_UI" != "1" ]; then
            display_image_and_text "$LOGO" 35 25 \
                "Extraction completed with warnings. Check the log for details." 75
        fi
    else
        log_update_message "Extraction process completed successfully"
        if [ "$SUPPRESS_PROGRESS_UI" != "1" ]; then
            display_image_and_text "$LOGO" 35 25 "Extraction completed!" 75
        fi
    fi

    return "$RET"
}


##### SDL GAMECONTROLLER MAPPING #####

# Hand SDL a GameController mapping for the built-in pad.
#
# Nothing on BaseOS ships one. Every H700 Anbernic reports the same GUID and the
# name "ANBERNIC-keys", so SDL cannot pick a per-model mapping by itself either -
# AnbernicXXCommon.cfg selects the right one by BASEOS_TARGET and leaves it in
# SDL_GAMECONTROLLER_MAP. Without it a pad enumerates as a plain joystick with
# is_gamecontroller false, and anything driving input through SDL_GameController
# silently does nothing: PPSSPP, PICO-8, vtree and gptokeyb have all hit this.
#
# There are two forms and picking the wrong one is not a failure, it is a
# symmetric swap - A and B doing each other's job, Y doing what X should - which
# is easy to misread as a broken mapping rather than the wrong convention:
#
#   (default)     label-named. "a" is the button *marked* A. What RetroArch and
#                 PPSSPP want, since A is confirm on a Nintendo layout.
#   positional    SDL's own convention: a South, b East, x West, y North. What
#                 an app wants when it speaks raw SDL - gptokeyb's .gptk files -
#                 or when it already applies its own Nintendo correction, as
#                 vtree does with spruce's nintendo-button-labels patch.
#
# Only the four face buttons differ between the two; shoulders, triggers, stick
# clicks and the d-pad are identical. Safe to call anywhere: it is a no-op when
# SDL_GAMECONTROLLER_MAP is unset, which is every non-BaseOS device.
#
# Usage:
#   export_sdl_gamecontroller_map              # label-named
#   export_sdl_gamecontroller_map positional   # SDL convention
export_sdl_gamecontroller_map() {
    [ -n "$SDL_GAMECONTROLLER_MAP" ] || return 0

    case "$1" in
        positional)
            SDL_GAMECONTROLLERCONFIG="$(printf '%s' "$SDL_GAMECONTROLLER_MAP" \
                | sed -e 's/a:\([^,]*\),b:\([^,]*\)/a:\2,b:\1/' \
                      -e 's/x:\([^,]*\),y:\([^,]*\)/x:\2,y:\1/')"
            ;;
        *)
            SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLER_MAP"
            ;;
    esac

    export SDL_GAMECONTROLLERCONFIG
}


##### WIFI HANDLING #####

disable_wifi() {
    ifconfig wlan0 down         2>/dev/null
    rm -f /tmp/wifion           2>/dev/null
    touch /tmp/wifioff          2>/dev/null
    killall -9 wpa_supplicant   2>/dev/null
    # Stop whichever client this device actually started. Naming udhcpc here
    # only works for as long as every device uses udhcpc; a device that
    # overrides device_start_dhcp_client would have been left with its client
    # still holding the interface after "WiFi off".
    device_stop_dhcp_client
    log_message "WiFi turned off"
    device_wifi_power_off
}

# Read the -c argument out of a running wpa_supplicant's cmdline. Accepts both
# "-c /path" and "-cpath"; prints nothing if there is no -c.
wpa_conf_path_of_pid() {
    [ -n "$1" ] || return 0
    tr '\0' '\n' < "/proc/$1/cmdline" 2>/dev/null | awk '
        prev == "-c" { print; exit }
        /^-c./       { sub(/^-c/, ""); print; exit }
        { prev = $0 }
    '
}

# Merge the network blocks of another wpa_supplicant.conf into ours, skipping
# any SSID we already have. Used when taking the radio over from whatever
# brought it up before us.
#
# Nothing here may log block contents: they hold pre-shared keys in the clear.
# Only counts and paths are logged.
import_wpa_networks_from() {
    FOREIGN_CONF="$1"

    [ -n "$FOREIGN_CONF" ] || return 0
    [ -f "$FOREIGN_CONF" ] || return 0
    [ -n "$WPA_SUPPLICANT_FILE" ] || return 0
    [ "$FOREIGN_CONF" = "$WPA_SUPPLICANT_FILE" ] && return 0

    TMP_IMPORT="/tmp/wpa_import.$$"
    awk -v ours="$WPA_SUPPLICANT_FILE" '
        BEGIN {
            while ((getline line < ours) > 0) {
                if (line ~ /^[ \t]*ssid=/) {
                    sub(/^[ \t]*ssid=/, "", line)
                    have[line] = 1
                }
            }
            close(ours)
        }
        # No brace in either regex: busybox awk parses an unescaped { as the
        # start of an interval expression and rejects the whole pattern with
        # "Invalid contents of {}". Matching "network=" is enough to open a
        # block, and $1 == "}" closes one whatever the indentation.
        /^[ \t]*network[ \t]*=/ { inblock = 1; n = 0; ssid = "" }
        inblock {
            buf[n++] = $0
            if ($0 ~ /^[ \t]*ssid=/) { ssid = $0; sub(/^[ \t]*ssid=/, "", ssid) }
            if ($1 == "}") {
                inblock = 0
                if (ssid != "" && !(ssid in have)) {
                    have[ssid] = 1
                    printf "\n"
                    for (i = 0; i < n; i++) print buf[i]
                }
            }
        }
    ' "$FOREIGN_CONF" > "$TMP_IMPORT" 2>/dev/null

    NEW_COUNT=$(grep -c '^[[:space:]]*network[[:space:]]*=' "$TMP_IMPORT" 2>/dev/null)
    if [ "${NEW_COUNT:-0}" -gt 0 ]; then
        cat "$TMP_IMPORT" >> "$WPA_SUPPLICANT_FILE"
        log_message "Imported $NEW_COUNT network(s) from $FOREIGN_CONF"
    else
        log_message "No new networks to import from $FOREIGN_CONF"
    fi
    rm -f "$TMP_IMPORT"
}

enable_wifi() {
    device_wifi_power_on

    # Everything below assumes wlan0 exists. On SDIO parts it sometimes does
    # not - the radio fails to enumerate and the interface is never created -
    # and then wpa_supplicant, udhcpc and the WiFi menu all quietly operate on
    # nothing. Give the device a chance to bring it back first.
    device_ensure_wifi_interface

    rm -f /tmp/wifioff          2>/dev/null
    touch /tmp/wifion           2>/dev/null
    ifconfig wlan0 up           2>/dev/null

    # Some hosts own the radio themselves. On the RGB30 that is connman, which
    # does association AND DHCP, so starting our own wpa_supplicant against it
    # is two daemons fighting over one interface - the same class of mistake
    # the Anbernic XX line made by running dhclient beside udhcpc.
    if device_manages_own_wifi; then
        log_message "Host OS manages WiFi; not starting wpa_supplicant or a DHCP client"
        /mnt/SDCARD/spruce/scripts/networkservices.sh &
        device_extra_wifi_setup
        return 0
    fi

    # wpa_supplicant refuses to start without its config file, and every start
    # below passes -c without checking that the file is there. It fails in the
    # background where nobody sees it, udhcpc starts anyway so the interface
    # looks half alive, and the UI sits on "Scanning for networks..." forever -
    # the scanner is only "wpa_cli scan", and wpa_cli has no daemon to ask.
    #
    # Seed the same two lines PyUI writes rather than assume something else
    # created it. ctrl_interface is what wpa_cli connects to; update_config=1
    # lets wpa_supplicant persist networks added from the UI.
    if [ -n "$WPA_SUPPLICANT_FILE" ] && [ ! -f "$WPA_SUPPLICANT_FILE" ]; then
        mkdir -p "$(dirname "$WPA_SUPPLICANT_FILE")" 2>/dev/null
        printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n\n' > "$WPA_SUPPLICANT_FILE"
        log_message "Created missing $WPA_SUPPLICANT_FILE"
    fi

    # check if WPA supplicant needs to be started or restarted
    WPA_PID=$(pgrep -f "wpa_supplicant.*wlan0")
    if [ -n "$WPA_PID" ]; then
        WPA_CMDLINE=$(tr '\0' ' ' < /proc/$WPA_PID/cmdline)
        if ! echo "$WPA_CMDLINE" | grep -q -- "-c $WPA_SUPPLICANT_FILE"; then
            # Somebody else's wpa_supplicant owns the radio - on BaseOS devices
            # that is the OS underneath us, and it is very likely ASSOCIATED
            # RIGHT NOW. spruce takes ownership here by design, but taking it by
            # killing that process and starting ours against a config that may
            # hold no networks at all just drops a working connection, and the
            # user sees WiFi die a few seconds into boot for no reason.
            #
            # Carry its networks across first, then take over.
            log_message "wpa_supplicant using wrong config; taking over with $WPA_SUPPLICANT_FILE"
            import_wpa_networks_from "$(wpa_conf_path_of_pid "$WPA_PID")"
            kill -9 "$WPA_PID" 2>/dev/null
            sleep 1
            wpa_supplicant -B -D nl80211 -i wlan0 -c "$WPA_SUPPLICANT_FILE"
            log_message "wpa_supplicant was running with the wrong conf so restarted"
        else
            log_message "wpa_supplicant was running with the correct conf file already"
        fi
    else    # wpa_supplicant was not running at all, so start it
        wpa_supplicant -B -D nl80211 -i wlan0 -c "$WPA_SUPPLICANT_FILE"
        log_message "Launching wpa_supplicant"
    fi
    device_start_dhcp_client
    /mnt/SDCARD/spruce/scripts/networkservices.sh &
    log_message "WiFi turned on"

    device_extra_wifi_setup
}

enable_or_disable_wifi_per_system_json() {
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
        disable_wifi
    else
        enable_wifi
    fi
}

restart_wifi() {
    # Requires PLATFORM and WPA_SUPPLICANT_FILE to be set
    log_message "Restarting Wi-Fi interface wlan0"
    disable_wifi
    sleep 1
    enable_wifi
}

# Does this interface hold an address?
#
# Ask iproute2 and net-tools both, and believe either. An ifconfig-only version
# always answered "no address" on Debian, which does not ship net-tools:
# network_is_connected never returned true, networkservices.sh waited on it
# forever, and SSH, Samba, SFTPGo, syncthing and time sync were never started.
# Nothing logged an error - that loop waits indefinitely on purpose.
#
# Believing only ip would trade that for the same bug on any busybox device
# whose ip applet does not take these options, so ask both.
iface_has_address() {
    _iface="$1"

    [ -n "$_iface" ] || return 1

    if command -v ip >/dev/null 2>&1; then
        if ip -o addr show dev "$_iface" 2>/dev/null | grep -q "inet"; then
            return 0
        fi
    fi

    if command -v ifconfig >/dev/null 2>&1; then
        if ifconfig "$_iface" 2>/dev/null | grep -qE "inet |inet6 "; then
            return 0
        fi
    fi

    return 1
}

network_is_connected() {
    CHECK_ETH="${1:-false}" # Defaults to false if no argument

	iface_up=false
    wifi_iface=$(ls /sys/class/net/ | grep wlan | head -1)

    if iface_has_address "$wifi_iface"; then
        iface_up=true
    fi

    if [ "$CHECK_ETH" = true ]; then
        if iface_has_address eth0; then
            iface_up=true
        fi
    fi

	if $iface_up; then
		if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
			return 0 # Success
        fi
	fi

	return 1 # No network connection
}

check_and_connect_wifi() {

    timeout=60
    start_time=$(date +%s)

    # Initial connection check
    if network_is_connected true; then
        log_message "Active network connection verified"
        return 0
    fi

    # Check if device has wifi available
    if ! device_wifi_is_available; then
        return 1
    fi

    log_message "Attempting to connect to WiFi"
    start_pyui_message_writer 1
    restart_wifi

    display_image_and_text "/mnt/SDCARD/spruce/imgs/signal.png" 35 20 \
        "Waiting to connect....\nPress START to continue anyway." 75

    rm -f /tmp/ge_out 2>/dev/null

    # Start getevent in background
    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" > /tmp/ge_out &
    GE_PID=$!

    while true; do
        # 1. Check for user input
        if line=$(tail -n 1 /tmp/ge_out 2>/dev/null); then
            case "$line" in
                *"key $B_START"* | *"key $B_START_2"*)
                    log_message "WiFi connection cancelled by user"
                    kill "$GE_PID" 2>/dev/null
                    display_image_and_text "/mnt/SDCARD/spruce/imgs/notfound.png" 35 25 \
                        "Proceeding before connected to wifi." 75
                    sleep 2
                    stop_pyui_message_writer
                    return 1
                    ;;
            esac
        fi

        # 2. Check for successful connection
        if network_is_connected; then
            log_message "Successfully connected to WiFi"
            kill "$GE_PID" 2>/dev/null
            stop_pyui_message_writer
            return 0
        fi

        # 3. Check for timeout
        current_time=$(date +%s)
        if [ $((current_time - start_time)) -ge $timeout ]; then
            log_message "WiFi connection timed out after $timeout seconds"
            kill "$GE_PID" 2>/dev/null
            stop_pyui_message_writer
            return 1
        fi

        sleep 0.1
    done
    stop_pyui_message_writer
}

##### ACTIVITY TRACKER STUFF #####

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
