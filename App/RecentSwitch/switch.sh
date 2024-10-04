#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="/mnt/SDCARD/App/RecentSwitch/switching.png"
CONFIG_FILE="/mnt/SDCARD/App/RecentSwitch/config.json"
MAINUI_PATH="/mnt/SDCARD/miyoo/app/mainui"
RECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/recents/mainui"
NORECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/norecents/mainui"

if [ ! -f "$IMAGE_PATH" ]; then
    log_message "Image file not found at $IMAGE_PATH"
    exit 1
fi

show_image "$IMAGE_PATH"

sleep 2

toggle_mainui() {
    if [ -f "$MAINUI_PATH" ]; then
        mv "$MAINUI_PATH" "${MAINUI_PATH}.bak"

        if diff -q "${MAINUI_PATH}.bak" "$RECENTS_MAINUI_PATH" >/dev/null; then
            cp "$NORECENTS_MAINUI_PATH" "$MAINUI_PATH"
            sed -i 's|- On|- Off|' "$CONFIG_FILE"
            log_message "Switched to NO RECENTS mode"
        else
            cp "$RECENTS_MAINUI_PATH" "$MAINUI_PATH"
            sed -i 's|- Off|- On|' "$CONFIG_FILE"
            log_message "Switched to RECENTS mode"
        fi

        rm "${MAINUI_PATH}.bak"
    else
        log_message "MainUI file not found: $MAINUI_PATH"
    fi
}

toggle_mainui

kill_images
