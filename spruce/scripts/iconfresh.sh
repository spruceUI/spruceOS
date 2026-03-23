#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

get_theme_path() {
	jq -r '.theme' "$SYSTEM_JSON"
}

LOADING_IMG=/mnt/SDCARD/Themes/loading.png

# Get background and last loading images
THEME_NAME=$(get_theme_path)
BG_IMG="/mnt/SDCARD/Themes/${THEME_NAME}/skin/app_loading_bg.png"
LAST_IMG=$(find "/mnt/SDCARD/Themes/${THEME_NAME}/skin/" -maxdepth 1 -name 'app_loading_0*.png' -type f | tail -n 1)

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
