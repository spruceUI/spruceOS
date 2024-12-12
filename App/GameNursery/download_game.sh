#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

JSON_FILE="$1"
TMP_DIR="/tmp/nursery"
GAME_NAME="$(jq -r '.display' "$JSON_FILE")"
GAME_URL="$(jq -r '.url' "$JSON_FILE")"
ZIP_NAME="$(basename "$GAME_URL")"
BG_IMG=/mnt/SDCARD/spruce/imgs/bg_tree.png

# attempt to download the game
display -i "$BG_IMG" -t "Now downloading $GAME_NAME!"
if ! curl -s -k -L -o "$TMP_DIR/$ZIP_NAME" "$GAME_URL"; then
	log_message "Game Nursery: Failed to download $GAME_NAME from $GAME_URL"
	display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to download $GAME_NAME from repository. Please try again later."
	exit 1
fi

# attempt to unzip the game
display -i "$BG_IMG" -t "Now installing $GAME_NAME!"
cd "/mnt/SDCARD"
if ! 7zr x -y -scsUTF-8 "$TMP_DIR/$ZIP_NAME" >/dev/null 2>&1; then
	display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to extract latest game info files. Please try again later."
	rm -f "$JSON_DIR/INFO.7z" >/dev/null 2>&1
	log_message "Game Nursery: Failed to extract release info from INFO.7z file"
	exit 1
else
	display -d 2 -i "$BG_IMG" -t "$GAME_NAME installed successfully!"
	log_message "Extraction process completed successfully"
fi
