# Function summaries:
# acknowledge: Waits for user to press A, B, or Start button
# cores_online: Sets the number of CPU cores to be online
# display: Displays text on the screen with various options
# exec_on_hotkey: Executes a command when specific buttons are pressed
# flag_check: Checks if a flag exists
# flag_add: Adds a flag
# flag_remove: Removes a flag
# get_button_press: Returns the name of the last button pressed
# kill_images: Kills all show processes
# log_message: Logs a message to a file
# show_image: Displays an image for a specified duration
# vibrate: Vibrates the device for a specified duration

# This is a collection of functions that are used in multiple scripts
# Please do not add any dependencies here, this file is meant to be self-contained
# Keep methods in alphabetical order

# Gain access to the helper variables by adding this to the top of your script:
# . /mnt/SDCARD/spruce/scripts/helperFunctions.sh

DISPLAY_TEXT_FILE="/mnt/SDCARD/spruce/bin/display_text.elf"
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

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


# Call this to set the number of CPU cores to be online
# Usage: cores_online [number of cores]
# Default is 2 core
cores_online(){
    local num_cores=${2:-1}  # Default to 2 if no argument is provided
    
    # Ensure the input is between 2 and 4
    if [ "$num_cores" -lt 2 ]; then
        num_cores=2
    elif [ "$num_cores" -gt 4 ]; then
        num_cores=4
    fi

    echo "Setting $num_cores CPU core(s) online"

    # Always keep CPU0 online
    echo 1 > /sys/devices/system/cpu/cpu0/online

    # Set the state for CPU1-3 based on the requested number of cores
    if [ "$num_cores" -ge 2 ]; then
        echo 1 > /sys/devices/system/cpu/cpu1/online
    else
        echo 0 > /sys/devices/system/cpu/cpu1/online
    fi

    if [ "$num_cores" -ge 3 ]; then
        echo 1 > /sys/devices/system/cpu/cpu2/online
    else
        echo 0 > /sys/devices/system/cpu/cpu2/online
    fi

    if [ "$num_cores" -eq 4 ]; then
        echo 1 > /sys/devices/system/cpu/cpu3/online
    else
        echo 0 > /sys/devices/system/cpu/cpu3/online
    fi
}

DEFAULT_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayText.png"
CONFIRM_IMAGE="/mnt/SDCARD/miyoo/res/imgs/displayTextConfirm.png"
# Call this to display text on the screen
# IF YOU CALL THIS YOUR SCRIPT NEEDS TO CALL display_kill()
# It's possible to leave a display process running
# Usage: display [options]
# Options:
#   -i, --image <path>    Image path (default: DEFAULT_IMAGE)
#   -t, --text <text>     Text to display
#   -d, --delay <seconds> Delay in seconds (default: 0)
#   -s, --size <size>     Text size (default: 36)
#   -p, --position <pos>  Text position (top, center, bottom) (default: center)
#   -a, --align <align>   Text alignment (left, middle, right) (default: middle)
#   -w, --width <width>   Text width (default: 600)
#   -c, --color <color>   Text color in RGB format (default: ffffff)
#   -f, --font <path>     Font path (optional)
#   -o, --okay            Use CONFIRM_IMAGE instead of DEFAULT_IMAGE and runs acknowledge()
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000
# Calling display with -o will use the CONFIRM_IMAGE instead of DEFAULT_IMAGE
display() {
    local image="$DEFAULT_IMAGE" text="" delay=0 size=30 position="center" align="middle" width=600 color="ffffff" font=""
    local use_confirm_image=false
    local run_acknowledge=false
    
    display_kill

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--image) image="$2"; shift ;;
            -t|--text) text="$2"; shift ;;
            -d|--delay) delay="$2"; shift ;;
            -s|--size) size="$2"; shift ;;
            -p|--position) position="$2"; shift ;;
            -a|--align) align="$2"; shift ;;
            -w|--width) width="$2"; shift ;;
            -c|--color) color="$2"; shift ;;
            -f|--font) font="$2"; shift ;;
            -o|--okay) use_confirm_image=true; run_acknowledge=true ;;
            *) log_message "Unknown option: $1"; return 1 ;;
        esac
        shift
    done
    if [[ -z "$text" ]]; then
        log_message "Error: Text is required"
        return 1
    fi
    if [[ "$use_confirm_image" = true ]]; then
        image="$CONFIRM_IMAGE"
    fi
    local r="${color:0:2}"
    local g="${color:2:2}"
    local b="${color:4:2}"
    # Log the final command
    local command="$DISPLAY_TEXT_FILE \"$image\" \"$text\" \"$delay\" \"$size\" \"$position\" \"$align\" \"$width\" \"$r\" \"$g\" \"$b\" \"$font\""
    #log_message "Executing display command: $command"
    
    # Execute the command in the background if delay is 0
    if [[ "$delay" -eq 0 ]]; then
        $DISPLAY_TEXT_FILE "$image" "$text" $delay $size $position $align $width $r $g $b $font &
        local exit_code=$?
        #log_message "display command started in background with PID $!"
        
        # Run acknowledge if -o or --okay was used
        if [[ "$run_acknowledge" = true ]]; then
            acknowledge
        fi
    else
        # Execute the command and capture its output
        local output
        output=$($DISPLAY_TEXT_FILE "$image" "$text" $delay $size $position $align $width $r $g $b $font 2>&1)
        local exit_code=$?
        # Log the output and exit code
        #log_message "display command output: $output"
        #log_message "display command exit code: $exit_code"
    fi

    # Return the exit code of the display command
    return $exit_code
}

# Call this to kill any display processes left running
# If you use display() at all you need to call this on all the possible exits of your script
display_kill(){
    kill -9 $(pgrep display)
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


# Check if a flag exists
# Usage: flag_check "flag_name"
# Returns 0 if the flag exists, 1 if it doesn't
flag_check() {
    local flag_name="$1"
    if [ -f "$FLAGS_DIR/${flag_name}.lock" ]; then
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
    local timeout=500  # Timeout in seconds
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


# Call this to kill any show/show_imimge processes left running
# If you use show()/show_image() at all you need to call this on all the possible exits of your script
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
# IF YOU CALL THIS YOUR SCRIPT NEEDS TO CALL kill_images()
# It's possible to leave a show_image() process running
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
