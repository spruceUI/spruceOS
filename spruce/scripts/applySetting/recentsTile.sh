
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

MAINUI_PATH="/mnt/SDCARD/miyoo/app/mainui"
RECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/recents/mainui"
NORECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/norecents/mainui"

toggle_mainui() {
    if [ -f "$MAINUI_PATH" ]; then
        mv "$MAINUI_PATH" "${MAINUI_PATH}.bak"

        if diff -q "${MAINUI_PATH}.bak" "$RECENTS_MAINUI_PATH" >/dev/null; then
            update_setting "recentsTile" "off"
            cp "$NORECENTS_MAINUI_PATH" "$MAINUI_PATH"
            log_message "Switched to NO RECENTS mode"
        else
            update_setting "recentsTile" "on"
            cp "$RECENTS_MAINUI_PATH" "$MAINUI_PATH"
            log_message "Switched to RECENTS mode"
        fi

        rm "${MAINUI_PATH}.bak"
    else
        log_message "MainUI file not found: $MAINUI_PATH"
    fi
}

toggle_mainui