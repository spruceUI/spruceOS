#!/bin/sh

WATCHED_FILE="/config/system.json"
SCRIPT_TO_RUN="/mnt/SDCARD/spruce/scripts/iconfresh.sh"
IMAGE_PATH="/mnt/SDCARD/spruce/imgs/refreshing.png"

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
        # show_image "$IMAGE_PATH" ### image has been removed
        THEME_PATH="$NEW_THEME_PATH"
        log_message "Theme path changed to: $THEME_PATH"
    fi
done
