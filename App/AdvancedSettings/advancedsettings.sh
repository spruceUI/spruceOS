#!/bin/sh

# Advanced Settings
# This script allows you to present settings to the user in a menu format.
# It reads from a file called options.txt which contains the settings.
# The script then displays the settings to the user and allows them to change them.
# The changes are saved to the spruce.cfg file. 
# In options.txt, the format is:
# "Category"|"Key"|"Text"|"Options"|"Default"
# "Category" is the category of the setting.
# "Key" is the key of the setting.
# "Text" is the text of the setting.
# "Options" are the options of the setting.
# "Default" is the default value of the setting.
# When adding new settings, make sure an empty line is added at the end of the file.
# Settings are separated by detecting new lines at the end.
# Categories are displayed in alphabetical order.

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

# Define the global variable
CHANGED_KEYS=""

# Function to load settings from spruce.cfg
load_advanced_settings() {
    log_message "Attempting to load settings"
    if [ ! -f "$SETTINGS_FILE" ]; then
        log_message "Settings file not found, creating default settings"
        touch "$SETTINGS_FILE"
    else
        log_message "Settings file found at $SETTINGS_FILE"
    fi

    while IFS='|' read -r category key text options default; do
        key=$(echo "$key" | tr -d '"')
        default=$(echo "$default" | tr -d '"' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if ! grep -q "^$key=" "$SETTINGS_FILE"; then
            printf "%s=%s\n" "$key" "$default" >> "$SETTINGS_FILE"
            log_message "Added missing setting: $key=$default"
        fi
    done < "$OPTIONS_FILE"
}

# Function to save settings to spruce.cfg
save_advanced_settings() {
    log_message "Saving settings to $SETTINGS_FILE"
    local changed_keys=""
    while IFS='|' read -r category key text options default; do
        key=$(echo "$key" | tr -d '"')
        old_value=$(grep "^$key=" "$SETTINGS_FILE" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        new_value=$(grep "^$key=" "$SETTINGS_FILE" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$new_value" ] && [ "$old_value" != "$new_value" ]; then
            sed -i "s|^$key=.*|$key=$new_value|" "$SETTINGS_FILE"
            changed_keys="$changed_keys $key"
        fi
    done < "$OPTIONS_FILE"
    
    # Set the global variable with the list of changed keys
    CHANGED_KEYS="$changed_keys"
}

ramp_up_cpu() {
    if [ "$1" = "true" ]; then
        echo "Ramping up CPU cores"
        echo 1 > /sys/devices/system/cpu/cpu0/online
        echo 1 > /sys/devices/system/cpu/cpu1/online
        echo 1 > /sys/devices/system/cpu/cpu2/online
        echo 0 > /sys/devices/system/cpu/cpu3/online
    else
        echo "Ramping down CPU cores 1-3"
        echo 0 > /sys/devices/system/cpu/cpu3/online
        echo 0 > /sys/devices/system/cpu/cpu2/online
        echo 0 > /sys/devices/system/cpu/cpu1/online
        # Keep CPU0 always online
        echo 1 > /sys/devices/system/cpu/cpu0/online
    fi
}

# Function to display current setting
display_current_setting() {
    local category="$1"
    local key="$2"
    local value=$(grep "^$key=" "$SETTINGS_FILE" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local line=$(grep "^\"$category\"|\"$key\"" "$OPTIONS_FILE")
    local text=$(echo "$line" | cut -d'|' -f3 | sed 's/^"//;s/"$//')
    
    if [ -n "$text" ]; then
        log_message "Displaying setting: $text: $value"
        local category_image="$BASE_DIR/imgs/${category}.png"
        [ -f "$category_image" ] || category_image="$BASE_IMAGE"
        display_text -i "$category_image" -t "$text:
$value" -p middle -s 40
    else
        log_message "Error: Text not found for key $key in category $category"
        display_text -i "$BASE_IMAGE" -t "Error: Setting not found" -p middle -s 44
    fi
}

# Function to handle changed settings
handle_changed_settings() {
    log_message "Handling changed settings: $CHANGED_KEYS"
    for key in $CHANGED_KEYS; do
        case "$key" in
            "some_setting_key")
                # Run script for some_setting_key
                /path/to/script_for_some_setting.sh
                ;;
            "another_setting_key")
                # Run script for another_setting_key
                /path/to/script_for_another_setting.sh
                ;;
            # Add more cases as needed
        esac
    done
}

# Main menu loop
main_settings_menu() {
    log_message "Entering main menu"
    current_category_index=0
    current_option_index=0

    # Get unique categories
    categories=$(cut -d'|' -f1 "$OPTIONS_FILE" | sort -u | tr -d '"')
    total_categories=$(echo "$categories" | wc -l)

    while true; do
        current_category=$(echo "$categories" | sed -n "$((current_category_index + 1))p")
        category_options=$(grep "^\"$current_category\"" "$OPTIONS_FILE")
        total_options=$(echo "$category_options" | wc -l)

        current_line=$(echo "$category_options" | sed -n "$((current_option_index + 1))p")
        current_key=$(echo "$current_line" | cut -d'|' -f2 | tr -d '"')

        display_current_setting "$current_category" "$current_key"

        button=$(get_button_press)
        log_message "Button pressed: $button"
        case "$button" in
            "UP")
                current_option_index=$((current_option_index - 1))
                [ "$current_option_index" -lt 0 ] && current_option_index=$((total_options - 1))
                log_message "Moving up. New index: $current_option_index"
                ;;
            "DOWN")
                current_option_index=$((current_option_index + 1))
                [ "$current_option_index" -ge "$total_options" ] && current_option_index=0
                log_message "Moving down. New index: $current_option_index"
                ;;
            "L1"|"L2")
                current_category_index=$((current_category_index - 1))
                [ "$current_category_index" -lt 0 ] && current_category_index=$((total_categories - 1))
                current_option_index=0
                log_message "Moving to previous category. New category index: $current_category_index"
                ;;
            "R1"|"R2")
                current_category_index=$((current_category_index + 1))
                [ "$current_category_index" -ge "$total_categories" ] && current_category_index=0
                current_option_index=0
                log_message "Moving to next category. New category index: $current_category_index"
                ;;
            "LEFT"|"RIGHT")
                options=$(echo "$current_line" | cut -d'|' -f4 | tr -d '"' | tr ',' ' ')
                current_value=$(grep "^$current_key=" "$SETTINGS_FILE" | cut -d'=' -f2-)
                new_value=$(change_setting "$current_value" "$options" "$button")
                sed -i "s/^$current_key=.*/$current_key=$new_value/" "$SETTINGS_FILE"
                log_message "Updated setting: $current_key=$new_value"
                ;;
            "A")
                save_advanced_settings
                display_text -t "Settings saved" -p bottom -s 26 -d 2
                log_message "Settings saved, changed keys: $CHANGED_KEYS"
                
                # Call the function to handle changed settings
                handle_changed_settings
                
                kill_images
                return
                ;;
            "B")
                log_message "Exiting main menu without saving"
                kill_images
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

    # If current value is not in options, set index to 0
    if [ $index -ge $option_count ]; then
        index=0
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

ramp_up_cpu true

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

ramp_up_cpu false 
log_message "Advanced Settings script completed"