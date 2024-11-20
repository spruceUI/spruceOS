#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/Samba/sambaFunctions.sh
. /mnt/SDCARD/spruce/bin/SSH/dropbearFunctions.sh
. /mnt/SDCARD/App/-OTA/downloaderFunctions.sh

# Define the function to check and unhide the firmware update app
check_and_handle_firmware_app() {
    VERSION="$(cat /usr/miyoo/version)"
    if [ "$VERSION" -lt 20240713100458 ]; then
        sed -i 's|"#label":|"label":|' "/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
    fi
}

# Function to check and hide the Update App if necessary
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

DEV_TASK='"" "Reapply Developer/Designer mode" "|" "run|off" "echo -n off" "/mnt/SDCARD/spruce/scripts/devconf.sh|" ""'


developer_mode_task() {
    if flag_check "developer_mode" || flag_check "designer_mode"; then
        # Add developer menu option to spruce_config if it doesn't exist
        if ! grep -q "Reapply Developer/Designer mode" /mnt/SDCARD/spruce/settings/spruce_config; then
            sed -i '/\[System\]/a '"$DEV_TASK"'' /mnt/SDCARD/spruce/settings/spruce_config
        fi
        
        if setting_get "samba" || setting_get "dropbear"; then
            # Loop until WiFi is connected
            while ! ifconfig wlan0 | grep -qE "inet |inet6 "; do
                sleep 0.5
            done
            
            if setting_get "samba" && ! pgrep "smbd" > /dev/null; then
                log_message "Dev Mode: Samba starting..."
                start_samba_process
            fi

            if setting_get "dropbear" && ! pgrep "dropbear" > /dev/null; then
                log_message "Dev Mode: Dropbear starting..."
                start_dropbear_process
            fi
            
        fi
    else
        # Remove the line if it exists and no flags are present
        sed -i '/Reapply Developer\/Designer mode/d' /mnt/SDCARD/spruce/settings/spruce_config
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


update_checker(){
    sleep 20
    check_for_update
}


