#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

JSON_FILE="$1"
TMP_DIR="/mnt/SDCARD/App/GameNursery/tmp"

SHORT_NAME="$(jq -r '.shortname' "$JSON_FILE")"
if [ "$SHORT_NAME" != "null" ] && [ -n "$SHORT_NAME" ]; then
    GAME_NAME="$SHORT_NAME"
else
    GAME_NAME="$(jq -r '.display' "$JSON_FILE")"
fi

GAME_URL="$(jq -r '.url' "$JSON_FILE")"
ZIP_NAME="$(basename "$GAME_URL")"

start_pyui_message_writer
log_and_display_message "Now downloading $GAME_NAME!"

TARGET_SIZE_BYTES="$(get_remote_filesize_bytes "$GAME_URL")"
TARGET_SIZE_KILO=$((TARGET_SIZE_BYTES / 1024))
TARGET_SIZE_MEGA=$((TARGET_SIZE_KILO / 1024))
REQUIRED_SPACE=$((TARGET_SIZE_MEGA * 3))
if [ "$REQUIRED_SPACE" -lt 3 ]; then
    REQUIRED_SPACE=3
fi
AVAILABLE_SPACE="$(df -m "/mnt/SDCARD" | awk 'NR==2{print $4}')"

log_message "Game Nursery: $AVAILABLE_SPACE MiB available; $REQUIRED_SPACE MiB required to install $GAME_NAME"
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
	log_and_display_message "You need at least $REQUIRED_SPACE MiB free to install $GAME_NAME. Please free up some space and try again later."
    sleep 4
	exit 1
else
	log_message "Game Nursery: Available space is sufficient. Proceeding to download $GAME_NAME"
fi

# initialize temporary nursery file directory

mkdir "$TMP_DIR" 2>/dev/null
cd "$TMP_DIR"
rm -r ./* 2>/dev/null

# attempt to download the game
log_and_display_message "Now downloading $GAME_NAME!"
if ! download_and_display_progress "$GAME_URL" "$TMP_DIR/$ZIP_NAME" "$GAME_NAME" "$TARGET_SIZE_BYTES"; then
	exit 1
fi

# attempt to unzip the game
log_and_display_message "Now installing $GAME_NAME!"
cd "/mnt/SDCARD"
if ! 7zr x -y -scsUTF-8 "$TMP_DIR/$ZIP_NAME" >/dev/null 2>&1; then
	log_and_display_message "Unable to extract $GAME_NAME. Please try again later."
	rm -f "$TMP_DIR/$ZIP_NAME" >/dev/null 2>&1
    sleep 4
	exit 1
else
	log_and_display_message "$GAME_NAME installed successfully!"
    sleep 2
	rm -f "$TMP_DIR/$ZIP_NAME" 2>/dev/null
fi

