#!/bin/sh

# Function to check and hide the Update App if necessary

# Define the function to check and unhide the firmware update app
check_and_handle_firmware_app() {
    VERSION="$(cat /usr/miyoo/version)"
    if [ "$VERSION" -lt 20240713100458 ]; then
        sed -i 's|"#label":|"label":|' "/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
    fi
}

check_and_hide_update_app() {
    . /mnt/SDCARD/Updater/updaterFunctions.sh
    if ! check_for_update_file; then
        sed -i 's|"label"|"#label"|' "/mnt/SDCARD/App/-Updater/config.json"
        log_message "No update file found; hiding Updater app"
    else
        sed -i 's|"#label"|"label"|' "/mnt/SDCARD/App/-Updater/config.json"
        log_message "Update file found; Updater app is visible"
    fi
}

rotate_logs() {
    local log_dir="/mnt/SDCARD/Saves/spruce"
    local log_target="$log_dir/spruce.log"
    local max_log_files=5

    # Create the log directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi

    # If spruce.log exists, move it to a temporary file
    if [ -f "$log_target" ]; then
        mv "$log_target" "$log_target.tmp"
    fi

    # Create a fresh spruce.log immediately
    touch "$log_target"

    # Perform log rotation in the background
    (
        # Rotate logs spruce5.log -> spruce4.log -> spruce3.log -> etc.
        i=$((max_log_files - 1))
        while [ $i -ge 1 ]; do
            if [ -f "$log_dir/spruce${i}.log" ]; then
                mv "$log_dir/spruce${i}.log" "$log_dir/spruce$((i+1)).log"
            fi
            i=$((i - 1))
        done

        # Move the temporary file to spruce1.log
        if [ -f "$log_target.tmp" ]; then
            mv "$log_target.tmp" "$log_dir/spruce1.log"
        fi
    ) &
}

set_usb_icon_from_theme(){
    THEME_JSON_FILE="/config/system.json"
    USB_ICON_SOURCE="/mnt/SDCARD/Icons/Default/App/usb.png"
    USB_ICON_DEST="/usr/miyoo/apps/usb_storage/usb_icon_80.png"

    if [ -f "$THEME_JSON_FILE" ]; then
        THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
        THEME_PATH="${THEME_PATH%/}/"
        [ "${THEME_PATH: -1}" != "/" ] && THEME_PATH="${THEME_PATH}/"
        APP_THEME_ICON_PATH="${THEME_PATH}Icons/App/"
        if [ -f "${APP_THEME_ICON_PATH}usb.png" ]; then
            mount -o bind "${APP_THEME_ICON_PATH}usb.png" "$USB_ICON_DEST"
        else
            mount -o bind "$USB_ICON_SOURCE" "$USB_ICON_DEST"
        fi
    fi
}



