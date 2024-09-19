#!/bin/sh

# Base directory containing the specific folders
APP_DIR="/mnt/SDCARD/App/"
BASE_DIR="/mnt/SDCARD/App/ExpertAppSwitch/"
CONFIG_FILE="${BASE_DIR}/config.json"

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

update_config_label() {
    local state=$1
    sed -i "s/\"label\": *\"[^\"]*\"/\"label\": \"EXPERT APPS - ${state}\"/" "$CONFIG_FILE"
}

if [ -f "${BASE_DIR}/.expert" ]; then
    # Expert mode is active, hide expert apps
    changed_folders=""
    find "$APP_DIR" -name "config.json" | while read -r config_file; do
        if grep -q '"expert": *true' "$config_file"; then
            sed -i 's/"label":/"#label":/' "$config_file"
            folder=$(dirname "$config_file")
            changed_folders="${changed_folders}${folder##*/} (off), "
        fi
    done
    # Remove trailing comma and space
    changed_folders=$(echo "$changed_folders" | sed 's/, $//')
    log_message "Expert apps turned off: $changed_folders"
    # Delete the .expert file
    rm "${BASE_DIR}/.expert"
    # Update the config.json label
    update_config_label "OFF"
else
    # Expert mode is not active, show expert apps
    changed_folders=""
    find "$APP_DIR" -name "config.json" | while read -r config_file; do
        if grep -q '"expert": *true' "$config_file"; then
            sed -i 's/"#label":/"label":/' "$config_file"
            folder=$(dirname "$config_file")
            changed_folders="${changed_folders}${folder##*/} (on), "
        fi
    done
    # Remove trailing comma and space
    changed_folders=$(echo "$changed_folders" | sed 's/, $//')
    log_message "Expert apps turned on: $changed_folders"
    # Create the .expert file
    touch "${BASE_DIR}/.expert"
    # Update the config.json label
    update_config_label "ON"
fi

# Run the additional script at the end
/mnt/SDCARD/App/IconFresh/iconfresh.sh
