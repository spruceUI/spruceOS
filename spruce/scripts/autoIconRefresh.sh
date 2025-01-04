#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ICONFRESH_ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

get_theme_path() {
    awk -F'"' '/"theme":/ {print $4}' "$SYSTEM_JSON" | sed 's:/*$:/:'
}

THEME_PATH=$(get_theme_path)

while true; do
    inotifywait -e modify "$SYSTEM_JSON"
    log_message "File $SYSTEM_JSON has been modified" -v

    NEW_THEME_PATH=$(get_theme_path)

    if [ "$NEW_THEME_PATH" != "$THEME_PATH" ]; then
        flag_add "themeChanged"
        killall -9 MainUI
        display --icon "$ICONFRESH_ICON" -t "Refreshing icons... please wait......"
        THEME_PATH="$NEW_THEME_PATH"
        log_message "Theme path changed to: $THEME_PATH"
    fi

    # avoid potential busy looping
    sleep 1
done
