#!/bin/sh

. "$HELPER_FUNCTIONS"

SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"

IMAGE_PATH_WIKI="${SDCARD_PATH}/.tmp_update/res/wiki.png"
FW_ICON="${SDCARD_PATH}/Themes/SPRUCE/icons/App/firmwareupdate.png"
IMAGE_PATH_ENJOY="${SDCARD_PATH}/.tmp_update/res/enjoy.png"

log_message "Starting firstboot script"

if flag_check "first_boot"; then
    show_image "${SDCARD_PATH}/.tmp_update/res/installing.png"
    log_message "First boot flag detected"
    
    # don't overwrite user's config if it's not a TRUE first boot
    if ! flag_check "config_copied"; then
        cp "${SDCARD_PATH}/.tmp_update/system.json" "$SETTINGS_FILE"
        flag_add "config_copied"
        sync
        sleep 5
        log_message "Copied system.json and created config_copied.lock"
    fi
    
    if [ -f "${SWAPFILE}" ]; then
        SWAPSIZE=$(du -k "${SWAPFILE}" | cut -f1)
        MINSIZE=$((128 * 1024))
        if [ "$SWAPSIZE" -lt "$MINSIZE" ]; then
            swapoff "${SWAPFILE}"
            rm "${SWAPFILE}"
            log_message "Removed undersized swap file"
        fi
    fi
    
    if [ ! -f "${SWAPFILE}" ]; then
        dd if=/dev/zero of="${SWAPFILE}" bs=1M count=128
        mkswap "${SWAPFILE}"
        sync
        log_message "Created new swap file"
    fi
    
    log_message "Running emu_setup.sh"
    /mnt/SDCARD/Emu/.emu_setup/emu_setup.sh
    
    log_message "Running emufresh.sh"
    /mnt/SDCARD/.tmp_update/scripts/emufresh.sh
    
    log_message "Running iconfresh.sh"
    show_image "/mnt/SDCARD/.tmp_update/res/iconfresh.png"
    /mnt/SDCARD/spruce/scripts/iconfresh.sh --silent

    log_message "Displaying wiki image"
    show_image "$IMAGE_PATH_WIKI" 5

    VERSION=$(cat /usr/miyoo/version)
    if [ "$VERSION" -lt 20240713100458 ]; then
        log_message "Detected firmware version $VERSION, suggesting update"
        display -i "$FW_ICON" -d 5 -p bottom -t "Visit the App section from the main menu to update your firmware to the latest version. It fixes the A30's Wi-Fi issues!"
    fi
    
    log_message "Displaying enjoy image"
    show_image "$IMAGE_PATH_ENJOY" 5

    flag_remove "first_boot"
    log_message "Removed first boot flag"
else
    log_message "First boot flag not found. Skipping first boot procedures."
fi

log_message "Finished firstboot script"
