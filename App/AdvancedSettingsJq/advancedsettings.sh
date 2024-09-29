#!/bin/sh

BASE_DIR="/mnt/SDCARD/App/AdvancedSettings"
OPTIONS_FILE="$BASE_DIR/options.json"
BASE_IMAGE="$BASE_DIR/imgs/default.png"

. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh

log_message "Starting Advanced Settings script"

# Function to display an option
display_option() {
    local display_name="$1"
    local current_value="$2"
    local category="$3"
    
    display_text -t "$category - $display_name: $current_value"
}

# Function to get the index of the current value in the options array
get_current_index() {
    current_value="$1"
    shift
    i=0
    for option in "$@"; do
        if [ "$option" = "$current_value" ]; then
            echo $i
            return
        fi
        i=$((i + 1))
    done
    echo 0
}

main_settings_menu() {
    options=$(jq -c '.' "$OPTIONS_FILE")
    num_options=$(echo "$options" | jq 'length')
    current_option=0
    current_values=""

    # Initialize current_values string
    i=0
    while [ $i -lt $num_options ]; do
        current_values="$current_values$(echo "$options" | jq -r ".[$i].DefaultValue"),"
        i=$((i + 1))
    done

    while true; do
        option=$(echo "$options" | jq -r ".[$current_option]")
        display_name=$(echo "$option" | jq -r '.DisplayName')
        category=$(echo "$option" | jq -r '.Category')
        current_value=$(echo "$current_values" | cut -d',' -f$((current_option + 1)))
        
        display_option "$display_name" "$current_value" "$category"

        button=$(get_button_press)
        log_message "Button pressed: $button"
        case "$button" in
            "UP")
                current_option=$((current_option - 1))
                if [ $current_option -lt 0 ]; then
                    current_option=$((num_options - 1))
                fi
                ;;
            "DOWN")
                current_option=$((current_option + 1))
                if [ $current_option -ge $num_options ]; then
                    current_option=0
                fi
                ;;
            "LEFT"|"RIGHT")
                option_values=$(echo "$option" | jq -r '.Options[]')
                num_values=$(echo "$option_values" | wc -l)
                current_index=$(get_current_index "$current_value" $option_values)
                
                if [ "$button" = "RIGHT" ]; then
                    current_index=$((current_index + 1))
                    if [ $current_index -ge $num_values ]; then
                        current_index=0
                    fi
                else
                    current_index=$((current_index - 1))
                    if [ $current_index -lt 0 ]; then
                        current_index=$((num_values - 1))
                    fi
                fi
                
                new_value=$(echo "$option_values" | sed -n "$((current_index + 1))p")
                current_values=$(echo "$current_values" | awk -v n=$((current_option + 1)) -v v="$new_value" 'BEGIN{FS=OFS=","} {$n=v; print}')
                ;;
            "A")
                # Save the current values
                for i in $(seq 0 $((num_options - 1))); do
                    local key=$(echo "$options" | jq -r ".[$i].Key")
                    echo "$current_values" | cut -d',' -f$((i + 1)) > "$BASE_DIR/$key.txt"
                done
                display_text -t "Settings saved" -d 2
                return
                ;;
            "B")
                return
                ;;
            "TIMEOUT")
                log_message "No button press detected, continuing loop"
                ;;
            *)
                log_message "Unhandled button press: '$button'"
                ;;
        esac
    done
}

# Start the main settings menu
main_settings_menu

log_message "Finished Advanced Settings script"