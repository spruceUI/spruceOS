#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ICONFRESH_ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

get_theme_path() {
    jq -r '.theme' "$SYSTEM_JSON"
}

THEME_PATH=$(get_theme_path)

while true; do
    inotifywait -e modify "$SYSTEM_JSON"
    log_message "File $SYSTEM_JSON has been modified" -v

    NEW_THEME_PATH=$(get_theme_path)

    if [ "$NEW_THEME_PATH" != "$THEME_PATH" ]; then
		/mnt/SDCARD/spruce/scripts/iconfresh.sh
    fi

    # avoid potential busy looping
    sleep 1
done
