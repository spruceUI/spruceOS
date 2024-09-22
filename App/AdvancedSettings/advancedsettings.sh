#!/bin/sh
BASE_DIR="/mnt/SDCARD/App/AdvancedSettings"
OPTIONS_FILE="$BASE_DIR/options.txt"
SETTINGS_FILE="/mnt/SDCARD/.tmp_update/spruce.cfg"
BASE_IMAGE="$BASE_DIR/imgs/default.png"

# Check if helperFunctions.sh exists and is readable
if [ ! -r "/mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh" ]; then
    echo "Error: helperFunctions.sh not found or not readable" >&2
    exit 1
fi

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh
log_message "helperFunctions.sh sourced successfully"

log_message "Starting Advanced Settings script"

# Check if OPTIONS_FILE exists and is readable
if [ ! -r "$OPTIONS_FILE" ]; then
    log_message "Error: OPTIONS_FILE ($OPTIONS_FILE) not found or not readable"
    exit 1
fi

log_message "OPTIONS_FILE found and is readable"

# Function to load settings from spruce.cfg
load_advanced_settings() {
    log_message "Attempting to load settings"
    if [ ! -f "$SETTINGS_FILE" ]; then
        log_message "Settings file not found, creating default settings"
        touch "$SETTINGS_FILE"
    else
        log_message "Settings file found at $SETTINGS_FILE"
    fi

    while IFS='|' read -r key text options default; do
        key=$(echo "$key" | tr -d '"')
        default=$(echo "$default" | tr -d '"')
        if ! grep -q "^$key=" "$SETTINGS_FILE"; then
            echo "$key=$default" >> "$SETTINGS_FILE"
            log_message "Added missing setting: $key=$default"
        fi
    done < "$OPTIONS_FILE"
}

# Function to save settings to spruce.cfg
save_advanced_settings() {
    log_message "Saving settings to $SETTINGS_FILE"
    for key in $(echo "$settings" | cut -d'=' -f1); do
        value=$(echo "$settings" | grep "^$key=" | cut -d'=' -f2-)
        sed -i "s/^$key=.*/$key=$value/" "$SETTINGS_FILE"
        log_message "Updated setting: $key=$value"
    done
}

# Function to display current setting
display_current_setting() {
    local key="$1"
    local value=$(grep "^$key=" "$SETTINGS_FILE" | cut -d'=' -f2-)
    local text=$(grep "^\"$key\"" "$OPTIONS_FILE" | cut -d'|' -f2 | tr -d '"')
    
    if [ -n "$text" ]; then
        log_message "Displaying setting: $text: $value"
        display_text -i "$BASE_IMAGE" -t "$text:$'\n'$value" -p middle -s 44
    else
        log_message "Error: Text not found for key $key"
        display_text -i "$BASE_IMAGE" -t "Error: Setting not found" -p middle -s 44
    fi
}

# Main menu loop
main_settings_menu() {
    log_message "Entering main menu"
    current_index=0
    total_options=$(wc -l < "$OPTIONS_FILE")

    while true; do
        current_key=$(sed -n "$((current_index + 1))p" "$OPTIONS_FILE" | cut -d'|' -f1 | tr -d '"')
        display_current_setting "$current_key"

        button=$(get_buttonpress)
        log_message "Button pressed: $button"
        case "$button" in
            "UP")
                current_index=$((current_index - 1))
                [ $current_index -lt 0 ] && current_index=$((total_options - 1))
                log_message "Moving up. New index: $current_index"
                ;;
            "DOWN")
                current_index=$((current_index + 1))
                [ $current_index -ge $total_options ] && current_index=0
                log_message "Moving down. New index: $current_index"
                ;;
            "LEFT"|"RIGHT")
                options=$(sed -n "$((current_index + 1))p" "$OPTIONS_FILE" | cut -d'|' -f3 | tr -d '"' | tr ',' ' ')
                current_value=$(grep "^$current_key=" "$SETTINGS_FILE" | cut -d'=' -f2-)
                new_value=$(change_setting "$current_value" "$options" "$button")
                sed -i "s/^$current_key=.*/$current_key=$new_value/" "$SETTINGS_FILE"
                log_message "Updated setting: $current_key=$new_value"
                ;;
            "")
                log_message "get_buttonpress returned empty string"
                ;;
            "A")
                save_advanced_settings
                display_text -t "Settings saved" -p bottom -s 26 -d 2
                log_message "Settings saved, exiting main menu"
                return
                ;;
            "B")
                log_message "Exiting main menu without saving"
                return
                ;;
            "TIMEOUT")
                log_message "No button press detected, continuing loop"
                ;;
            *)
                log_message "Unhandled button press: '$button'"
                ;;
        esac
        sleep 0.2
    done
}

change_setting() {
    local current_value="$1"
    local options="$2"
    local direction="$3"
    local new_index
    local option_count

    # Count the number of options
    option_count=$(echo "$options" | wc -w)

    # Find the current index in the options
    local index=0
    for option in $options; do
        if [ "$option" = "$current_value" ]; then
            break
        fi
        index=$((index + 1))
    done

    # If current value is not in options, set index to -1
    if [ $index -ge $option_count ]; then
        index=-1
    fi

    # Change the index based on the direction
    if [ "$direction" = "RIGHT" ]; then
        new_index=$((index + 1))
        [ $new_index -ge $option_count ] && new_index=0
    else
        new_index=$((index - 1))
        [ $new_index -lt 0 ] && new_index=$((option_count - 1))
    fi

    # Get the new value
    echo "$options" | cut -d' ' -f$((new_index + 1))
}

# Load settings
log_message "Calling load_settings function"
load_advanced_settings

# Parse current settings into a string
log_message "Parsing current settings"
settings=$(cat "$SETTINGS_FILE")
log_message "Loaded settings: $settings"

# Start the main menu
log_message "Starting main menu"
main_settings_menu

log_message "Advanced Settings script completed"