#!/bin/sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

MAINUI_PATH="/mnt/SDCARD/miyoo/app/mainui"
RECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/recents/mainui"
NORECENTS_MAINUI_PATH="/mnt/SDCARD/miyoo/app/norecents/mainui"

check_current_state() {
    if [ -f "$MAINUI_PATH" ] && diff -q "$MAINUI_PATH" "$RECENTS_MAINUI_PATH" >/dev/null; then
        echo -n "on"
    else
        echo -n "off"
    fi
}

set_recents_on() {
    if [ -f "$MAINUI_PATH" ]; then
        mv "$MAINUI_PATH" "${MAINUI_PATH}.bak"
        cp "$RECENTS_MAINUI_PATH" "$MAINUI_PATH"
        log_message "Set to RECENTS mode"
        update_setting "recentsTile" "on"
        rm "${MAINUI_PATH}.bak"
    else
        log_message "MainUI file not found: $MAINUI_PATH"
    fi
}

set_recents_off() {
    if [ -f "$MAINUI_PATH" ]; then
        mv "$MAINUI_PATH" "${MAINUI_PATH}.bak"
        cp "$NORECENTS_MAINUI_PATH" "$MAINUI_PATH"
        log_message "Set to NO RECENTS mode"
        update_setting "recentsTile" "off"
        rm "${MAINUI_PATH}.bak"
    else
        log_message "MainUI file not found: $MAINUI_PATH"
    fi
}

reapply_setting() {
    killall -9 MainUI
    setting_get "recentsTile"
    if [ $? -eq 0 ]; then
        set_recents_on
    else
        set_recents_off
    fi
}

case "$1" in
    "check")
        check_current_state
        exit 0
        ;;
    "on")
        set_recents_on
        ;;
    "off")
        set_recents_off
        ;;
    "reapply")
        reapply_setting
        ;;
    *)
        log_message "Invalid action for recentsTile.sh: $1"
        exit 1
        ;;
esac