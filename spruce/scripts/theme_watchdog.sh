#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

get_theme_path() {
    jq -r '.theme' "$SYSTEM_JSON"
}

new_theme_action() {
    case "$PLATFORM" in
        "Pixel2") set_loading_screen ;;
        *) return 0 ;;
    esac
}

THEME_PATH=$(get_theme_path)

while true; do
    inotifywait -e modify "$SYSTEM_JSON"
    log_message "File $SYSTEM_JSON has been modified" -v

    NEW_THEME_PATH=$(get_theme_path)

    if [ "$NEW_THEME_PATH" != "$THEME_PATH" ]; then
		new_theme_action
		THEME_PATH="$NEW_THEME_PATH"
    fi

    # avoid potential busy looping
    sleep 1
done
