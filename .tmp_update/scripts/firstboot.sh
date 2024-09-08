#!/bin/sh

SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"
FIRST_BOOT_FLAG="${SDCARD_PATH}/.tmp_update/flags/first_boot_flag"

IMAGE_PATH_WIKI="${SDCARD_PATH}/.tmp_update/res/wiki.png"
IMAGE_PATH_FIRMWARE="${SDCARD_PATH}/.tmp_update/res/firmware.png"
IMAGE_PATH_ENJOY="${SDCARD_PATH}/.tmp_update/res/enjoy.png"

if [ ! -f "$FIRST_BOOT_FLAG" ]; then
    [ ! -f "${SDCARD_PATH}/copy_config" ] && cp "${SDCARD_PATH}/.tmp_update/system.json" "$SETTINGS_FILE" && touch "${SDCARD_PATH}/copy_config" && sync && sleep 5
    
    if [ -f "${SWAPFILE}" ]; then
        SWAPSIZE=$(du -k "${SWAPFILE}" | cut -f1)
        MINSIZE=$((128 * 1024))
        [ "$SWAPSIZE" -lt "$MINSIZE" ] && swapoff "${SWAPFILE}" && rm "${SWAPFILE}"
    fi
    
    [ ! -f "${SWAPFILE}" ] && dd if=/dev/zero of="${SWAPFILE}" bs=1M count=128 && mkswap "${SWAPFILE}" && sync
    
    /mnt/SDCARD/.tmp_update/scripts/emufresh.sh
    /mnt/SDCARD/App/IconFresh/iconfresh.sh
    

    show "$IMAGE_PATH_WIKI" &
    SHOW_PID=$!
    sleep 5
    kill $SHOW_PID

    show "$IMAGE_PATH_FIRMWARE" &
    SHOW_PID=$!
    sleep 5
    kill $SHOW_PID
    
    show "$IMAGE_PATH_ENJOY" &
    SHOW_PID=$!
    sleep 10
    kill $SHOW_PID
    
    touch "$FIRST_BOOT_FLAG"
fi

