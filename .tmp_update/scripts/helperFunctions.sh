# This is a collection of functions that are used in multiple scripts
# Please do not add any dependencies here, this file is meant to be self-contained
# Keep methods in alphabetical order

# Gain access to the helper variables by adding this to the top of your script:
# . "$HELPER_FUNCTIONS"
# This is defined in the runtime.sh file
# or calling the file directly like:
# . /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh


# exports needed so we can refer to buttons by more memorable names
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

export B_VOLUP="volume up" # only registers on press and on change, not on release. No 1 or 0.
export B_VOLDOWN="key 1 114" # has actual key codes like the buttons
export B_VOLDOWN_2="volume down" # only registers on change. No 1 or 0.
export B_MENU="key 1 1" # surprisingly functions like a regular button
# export B_POWER # too complicated to bother with tbh


# Call this just by having "acknowledge" in your script
# This will pause until the user presses the A, B, or Start button
acknowledge(){
    messages_file="/var/log/messages"
	echo "ACKNOWLEDGE $(date +%s)" >> "$messages_file"

    while true; do
        last_line=$(tail -n 1 "$messages_file")

        case "$last_line" in
            *"enter_pressed"*|*"key 1 57"*|*"key 1 29"*)
                echo "ACKNOWLEDGED $(date +%s)" >> "$messages_file"
                break
                ;;
        esac

        sleep 1
    done
}

# Executes a command or script passed as the first argument, once 1-5 specific buttons
# which are passed as further arguments, are concurrently pressed.
# Call it with &, and don't forget to kill it whenever it is no longer needed.
# 
# Example Usage to reboot when all 4 face buttons are pressed at once:
# 
# exec_on_hotkey reboot "$B_A" "$B_B" "$B_X" "$B_Y" &
# hotkey_pid="$!"
# <the actual rest of your script>
# kill -9 "$hotkey_pid"
# 
exec_on_hotkey() {
	cmd="$1"
	key1="$2"
	key2="$3"
	key3="$4"
	key4="$5"
	key5="$6"
	key1_pressed=0
	key2_pressed=0
	key3_pressed=0
	key4_pressed=0
	key5_pressed=0
	num_keys="$#"
	num_keys=$((num_keys - 1))
	count=0
	messages_file="/var/log/messages"
	
	while [ 1 ]; do
	    last_line=$(tail -n 1 "$messages_file")
	    case "$last_line" in
	        *"$key1 1"*)
	            key1_pressed=1
	            ;;
	        *"$key1 0"*)
	            key1_pressed=0
	            ;;
		esac
		count="$key1_pressed"
		if [ "$#" -gt 2 ]; then
			case "$last_line" in
	        		*"$key2 1"*)
	            		key2_pressed=1
	            		;;
	        		*"$key2 0"*)
	            		key2_pressed=0
	            		;;
			esac
			count=$((count + key2_pressed))
		fi
		if [ "$#" -gt 3 ]; then
			case "$last_line" in
	        		*"$key3 1"*)
	            		key3_pressed=1
	            		;;
	        		*"$key3 0"*)
	            		key3_pressed=0
	            		;;
			esac
			count=$((count + key3_pressed))
		fi
		if [ "$#" -gt 4 ]; then
			case "$last_line" in
	        		*"$key4 1"*)
	            		key4_pressed=1
	            		;;
	        		*"$key4 0"*)
	            		key4_pressed=0
	            		;;
			esac
			count=$((count + key4_pressed))
		fi
		if [ "$#" -gt 5 ]; then
		    	case "$last_line" in
	        		*"$key5 1"*)
	            		key5_pressed=1
	            		;;
	        		*"$key5 0"*)
	            		key5_pressed=0
	            		;;
			esac
			count=$((count + key5_pressed))
		fi
# make sure count doesn't go beyond bounds for some reason.
		if [ $count -lt 0 ]; then
			count=0
		elif [ $count -gt "$num_keys" ]; then
			count="$num_keys"
		fi
# if all designated keys depressed, do the thing!	
		if [ $count -eq "$num_keys" ]; then
			"$cmd"
			# break
		fi
	done
}


# Call this to kill all show processes	
# Useful in some scenarios
kill_images(){
    killall -9 show
}



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
