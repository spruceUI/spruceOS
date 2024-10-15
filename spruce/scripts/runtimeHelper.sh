#!/bin/sh


rotate_logs() {
local log_file="/mnt/SDCARD/Saves/spruce/spruce.log"
local max_log_files=5
    # Rotate logs spruce5.log -> spruce4.log -> spruce3.log -> etc.
    for ((i=max_log_files-1; i>=1; i--)); do
        if [ -f "/mnt/SDCARD/Saves/spruce/spruce${i}.log" ]; then
            mv "/mnt/SDCARD/Saves/spruce/spruce${i}.log" "/mnt/SDCARD/Saves/spruce/spruce$((i+1)).log"
        fi
    done

    # If spruce.log exists, move it to spruce1.log
    if [ -f "$log_file" ]; then
        mv "$log_file" "/mnt/SDCARD/Saves/spruce/spruce1.log"
    fi

    # Create a fresh spruce.log
    touch "$log_file"
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