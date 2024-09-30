#!/bin/sh

. "$HELPER_FUNCTIONS"

SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"

IMAGE_PATH_WIKI="${SDCARD_PATH}/.tmp_update/res/wiki.png"
IMAGE_PATH_FIRMWARE="${SDCARD_PATH}/.tmp_update/res/firmware.png"
IMAGE_PATH_ENJOY="${SDCARD_PATH}/.tmp_update/res/enjoy.png"

log_message "Starting firstboot script"

if flag_check "first_boot"; then
    log_message "First boot flag detected"
    
    if [ ! -f "${SDCARD_PATH}/copy_config" ]; then
        cp "${SDCARD_PATH}/.tmp_update/system.json" "$SETTINGS_FILE"
        touch "${SDCARD_PATH}/copy_config"
        sync
        sleep 5
        log_message "Copied system.json and created copy_config flag"
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
    /mnt/SDCARD/.tmp_update/scripts/emu_setup.sh
    
    log_message "Running emufresh.sh"
    /mnt/SDCARD/.tmp_update/scripts/emufresh.sh
    
    log_message "Running iconfresh.sh"
    show_image "/mnt/SDCARD/.tmp_update/res/iconfresh.png"
    /mnt/SDCARD/App/IconFresh/iconfresh.sh --silent

    log_message "Displaying wiki image"
    show_image "$IMAGE_PATH_WIKI" 5

    log_message "Displaying firmware image"
    show_image "$IMAGE_PATH_FIRMWARE" 5

    log_message "Displaying enjoy image"
    show_image "$IMAGE_PATH_ENJOY" 5

    flag_remove "first_boot"
    log_message "Removed first boot flag"
else
    log_message "First boot flag not found. Skipping first boot procedures."
fi

log_message "Finished firstboot script"
