#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_recents_on() {
    log_message "Set to RECENTS mode"
    setting_update "recentsTile" "on"
}

set_recents_off() {
    log_message "Set to NO RECENTS mode"
    setting_update "recentsTile" "off"
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