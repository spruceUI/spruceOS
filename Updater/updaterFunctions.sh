APP_DIR="/mnt/SDCARD/App"

# Detect device and export to any script sourcing updaterFunctions
INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
*"sun8i"*)
	if [ -d /usr/miyoo ]; then
		export PLATFORM="A30"
	fi
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

# Key exports so we can refer to buttons by more memorable names
if [ "$PLATFORM" = "A30" ]; then
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

elif [ "$PLATFORM" = "Brick" ] || [ $PLATFORM = "SmartPro" ] || [ "$PLATFORM" = "Flip" ]; then
    export B_LEFT="key 3 16 -1"  # negative for left
    export B_RIGHT="key 3 16 1"  # positive for right
    export B_UP="key 3 17 -1"    # negative for up
    export B_DOWN="key 3 17 1"   # positive for down

    export STICK_LEFT="key 3 0 -32767" # negative for left
    export STICK_RIGHT="key 3 0 32767" # positive for right
    export STICK_UP="key 3 1 -32767"   # negative for up
    export STICK_DOWN="key 3 1 32767"  # positive for down

    export B_A="key 1 305"
    export B_B="key 1 304"
    export B_X="key 1 308"
    export B_Y="key 1 307"

    export B_L1="key 1 310"
    export B_L2="key 3 2 255" # 255 on push, nothing on release...
    export B_R1="key 1 311"
    export B_R2="key 3 5 255" # 255 on push, nothing on release...

    export B_L3="key 1 317" # also logs left fnkey stuff
    export B_R3="key 1 318" # also logs right fnkey stuff

    export B_START="key 1 315"
    export B_START_2="start_pressed" # only registers 0 on release, no 1.
    export B_SELECT="key 1 314"
    export B_SELECT_2="select_pressed" # registers both 1 and 0

    export B_VOLUP="key 1 115" # has actual key codes like the buttons
    export B_VOLDOWN="key 1 114" # has actual key codes like the buttons
    export B_VOLDOWN_2="volume down" # only registers 0 on release, no 1.
    export B_MENU="key 1 316"
fi

# add spruce/bin[64] folder to PATH
case "$PLATFORM" in
    "Brick" | "SmartPro" | "Flip" )
        PATH="/mnt/SDCARD/spruce/bin64:$PATH"
        ;;
    "A30" )
        PATH="/mnt/SDCARD/spruce/bin:$PATH"
        ;;
esac

acknowledge(){
    local messages_file="/var/log/messages"
	echo "ACKNOWLEDGE $(date +%s)" >> "$messages_file"

    while true; do
        last_line=$(tail -n 1 "$messages_file")

        case "$last_line" in
            *"enter_pressed"*|*"$B_A"*|*"$B_B"*)
                echo "ACKNOWLEDGED $(date +%s)" >> "$messages_file"
                break
                ;;
        esac

        sleep 0.1
    done
}

boost_processing() {
    /mnt/SDCARD/miyoo/utils/utils "performance" 4 1344 384 1080 1
    echo "CPU Mode set to PERFORMANCE"
    echo 1 >/sys/devices/system/cpu/cpu0/online 2>/dev/null
    echo 1 >/sys/devices/system/cpu/cpu1/online 2>/dev/null
    echo 1 >/sys/devices/system/cpu/cpu2/online 2>/dev/null
    echo 1 >/sys/devices/system/cpu/cpu3/online 2>/dev/null
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
	echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
}

check_for_update_file() {
    echo "Searching for update file"
    UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)
    echo "Found update file: $UPDATE_FILE"

    if [ -z "$UPDATE_FILE" ]; then
        echo "No update file found"
        return 1
    fi
    return 0
}

check_installation_validity() {
    # Check if .tmp_update folder exists
    if [ ! -d "/mnt/SDCARD/.tmp_update" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: .tmp_update folder does not exist"
        return 1
    fi

    # Check if .tmp_update/updater file exists
    if [ ! -f "/mnt/SDCARD/.tmp_update/updater" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: .tmp_update/updater file does not exist"
        return 1
    fi

    # Both files exist, installation is valid
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation appears to be valid"
    return 0
}

kill_network_services() {
    killall -9 dropbear
    killall -9 smbd
    killall -9 sftpgo
    killall -9 syncthing
}

read_only_check() {
    if [ $(mount | grep SDCARD | cut -d"(" -f 2 | cut -d"," -f1 ) == "ro" ]; then
        mount -o remount,rw /dev/mmcblk0p1 /mnt/SDCARD
    fi
}

verify_7z_content() {
    local archive="$1"
    local required_dirs=".tmp_update App spruce"
    local missing_dirs=""

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Verifying update file contents"

    # List contents of the archive and save to a temporary file
    local temp_list=$(mktemp)
    7zr l "$archive" >"$temp_list"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Archive contents:"
    cat "$temp_list"

    # Adding a skip for now
    #return 0

    for dir in $required_dirs; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Searching for directory: $dir"
        if grep -q "^.*D.*[[:space:]]$dir$" "$temp_list"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Found directory: $dir"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Directory not found: $dir"
            missing_dirs="$missing_dirs $dir"
        fi
    done

    rm -f "$temp_list"

    if [ -n "$missing_dirs" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Required director(ies)$missing_dirs not found in 7z file"
        return 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - All required directories found in 7z file"
    return 0
}

save_app_states() {
    local states_file="${1:-/tmp/app_states.txt}"
    
    # Clear existing states file if it exists
    : > "$states_file"
    
    # Find all config.json files in APP_DIR and process them
    find "$APP_DIR" -name "config.json" -type f | while read -r config_file; do
        # Get the parent directory name (app name)
        app_dir=$(dirname "$config_file")
        app_name=$(basename "$app_dir")
        
        # Skip if app_name starts with '-'
        case "$app_name" in
            -*) continue ;;
        esac
        
        # Check if the app is hidden (#label) or shown (label)
        if grep -q '"#label"' "$config_file"; then
            echo "$app_name:hidden" >> "$states_file"
        else
            echo "$app_name:shown" >> "$states_file"
        fi
    done
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - App states saved to $states_file"
}

restore_app_states() {
    local states_file="${1:-/tmp/app_states.txt}"
    
    if [ ! -f "$states_file" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - No app states file found"
        return 1
    fi
    
    while IFS=: read -r app_name state; do
        # Skip if app_name starts with '-'
        case "$app_name" in
            -*) continue ;;
        esac
        
        local config_file="$APP_DIR/$app_name/config.json"
        
        if [ -f "$config_file" ]; then
            if [ "$state" = "hidden" ]; then
                # Hide the app by replacing "label" with "#label"
                sed -i 's/"label"/"#label"/' "$config_file"
            else
                # Show the app by replacing "#label" with "label"
                sed -i 's/"#label"/"label"/' "$config_file"
            fi
        fi
    done < "$states_file"
    
    # Clean up the states file
    rm -f "$states_file"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - App states restored and temporary file removed"
}
