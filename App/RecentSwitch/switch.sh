#!/bin/sh

IMAGE_PATH="/mnt/SDCARD/App/RecentSwitch/switching.png"
CONFIG_FILE="/mnt/SDCARD/App/RecentSwitch/config.json"
MAINUI_PATH="/mnt/SDCARD/miyoo/app/mainui"
RECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/recents/mainui"
NORECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/norecents/mainui"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Image file not found at $IMAGE_PATH"
    exit 1
fi

show "$IMAGE_PATH" &

sleep 2

toggle_mainui() {
    if [ -f "$MAINUI_PATH" ]; then
        mv "$MAINUI_PATH" "${MAINUI_PATH}.bak"

        if diff -q "${MAINUI_PATH}.bak" "$RECENTS_MAINUI_PATH" >/dev/null; then
            cp "$NORECENTS_MAINUI_PATH" "$MAINUI_PATH"
            sed -i 's|"label": "RECENTS - ON"|"label": "RECENTS - OFF"|g' "$CONFIG_FILE"
            echo "Switched to NO RECENTS mode"
        else
            cp "$RECENTS_MAINUI_PATH" "$MAINUI_PATH"
            sed -i 's|"label": "RECENTS - OFF"|"label": "RECENTS - ON"|g' "$CONFIG_FILE"
            echo "Switched to RECENTS mode"
        fi

        rm "${MAINUI_PATH}.bak"
    else
        echo "MainUI file not found: $MAINUI_PATH"
    fi
}

toggle_mainui

killall -9 show
