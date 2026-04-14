#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

get_theme_path() {
    jq -r '.theme' "$SYSTEM_JSON"
}

new_theme_action() {
    LOADING_IMG=/mnt/SDCARD/Themes/loading.png

    # Get background and last loading images
    BG_IMG="/mnt/SDCARD/Themes/${1}/skin/app_loading_bg.png"
    LAST_IMG=$(find "/mnt/SDCARD/Themes/${1}/skin/" -maxdepth 1 -name 'app_loading_0*.png' -type f | tail -n 1)

    # If the background image doesn't exists use the default one
    if [ ! -f "$BG_IMG" ]; then
        BG_IMG="/mnt/SDCARD/Themes/SPRUCE/skin/app_loading_bg.png"
    fi

    # If there's no loading images use the default one
    if [ -z "$LAST_IMG" ]; then
        LAST_IMG="/mnt/SDCARD/Themes/SPRUCE/skin/app_loading_05.png"
    fi

    # Composite both images for the final loading image
    magick composite -gravity center "$LAST_IMG" "$BG_IMG" "$LOADING_IMG"

    set_loading_screen
}

THEME_PATH=$(get_theme_path)

while true; do
    inotifywait -e modify "$SYSTEM_JSON"
    log_message "File $SYSTEM_JSON has been modified" -v

    NEW_THEME_PATH=$(get_theme_path)

    if [ "$NEW_THEME_PATH" != "$THEME_PATH" ]; then
		new_theme_action "$NEW_THEME_PATH"
		THEME_PATH="$NEW_THEME_PATH"
    fi

    # avoid potential busy looping
    sleep 1
done
