#!/bin/sh

WATCHED_FILE="/config/system.json"
ICONFRESH_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/App/iconfresh.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

get_theme_path() {
    awk -F'"' '/"theme":/ {print $4}' "$WATCHED_FILE" | sed 's:/*$:/:'
}

THEME_PATH=$(get_theme_path)

while true; do
    inotifywait "$WATCHED_FILE"
    log_message "File $WATCHED_FILE has been modified" -v

    NEW_THEME_PATH=$(get_theme_path)

    if [ "$NEW_THEME_PATH" != "$THEME_PATH" ]; then
        flag_add "themeChanged"
        killall -9 MainUI
        display --icon "$ICONFRESH_ICON" -t "Refreshing icons... please wait......
     
     " -p bottom
        THEME_PATH="$NEW_THEME_PATH"
        log_message "Theme path changed to: $THEME_PATH"
    fi
done
