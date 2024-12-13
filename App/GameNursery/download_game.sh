#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

JSON_FILE="$1"
TMP_DIR="/mnt/SDCARD/App/GameNursery/tmp"
GAME_NAME="$(jq -r '.display' "$JSON_FILE")"
GAME_URL="$(jq -r '.url' "$JSON_FILE")"
ZIP_NAME="$(basename "$GAME_URL")"
BG_IMG=/mnt/SDCARD/spruce/imgs/bg_tree.png


download_progress() {
    filepath="$1"
    total_size_mb="$2"
    downloadBar="/mnt/SDCARD/App/-OTA/imgs/downloadBar.png"
    downloadFill="/mnt/SDCARD/App/-OTA/imgs/downloadFill.png"
    # Bar slider, 0.15 is 0, 0.85 is 100
    fill_scale_int=15  # 0.15 * 100
    sleep 2
    while true; do

        # Get current size in bytes using POSIX-compliant ls -l
        CURRENT_SIZE=$(ls -ln "$filepath" 2>/dev/null | awk '{print $5}')
        CURRENT_SIZE_MB=$((CURRENT_SIZE / 1048576))

        PERCENTAGE=$(((CURRENT_SIZE_MB * 100) / total_size_mb))

        log_message "Game Nursery: Download progress: $PERCENTAGE% (Size: $CURRENT_SIZE_MB / $total_size_mb MB)"

        # Calculate fill_scale_int based on percentage (15 to 85 range)
        # 0% = 15, 100% = 85, linear interpolation
        fill_scale_int=$((15 + (PERCENTAGE * 70 / 100)))

        display -i "$BG_IMG" -t "Now downloading $GAME_NAME!
        

        
$PERCENTAGE%" -p 135 --add-image $downloadFill 0.$(printf '%02d' $fill_scale_int) 240 left --add-image $downloadBar 1.0 240 middle

        # Exit if download is complete (>= 99%)
        if [ "$PERCENTAGE" -ge 99 ]; then
            log_message "Download complete"
            break
        fi
    done
}

# Verify enough space to download current game

TARGET_SIZE_BYTES="$(curl -k -I -L "$GAME_URL" 2>/dev/null | grep -i "Content-Length" | tail -n1 | cut -d' ' -f 2)"
TARGET_SIZE_KILO=$((TARGET_SIZE_BYTES / 1024))
TARGET_SIZE_MEGA=$((TARGET_SIZE_KILO / 1024))
REQUIRED_SPACE=$((TARGET_SIZE_MEGA * 3))
AVAILABLE_SPACE="$(df -m "/mnt/SDCARD" | awk 'NR==2{print $4}')"

log_message "Game Nursery: $REQUIRED_SPACE MiB required to install $GAME_NAME"
log_message "Game Nursery: $AVAILABLE_SPACE MiB available"
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
	log_message "Game Nursery: Not enough space. Aborting attempt to download $GAME_NAME"
	display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "You need at least $REQUIRED_SPACE MiB free to install $GAME_NAME. Please free up some space and try again later."
	exit 1
else
	log_message "Game Nursery: Available space is sufficient. Proceeding to download $GAME_NAME"
fi

# initialize temporary nursery file directory

mkdir "$TMP_DIR" 2>/dev/null
cd "$TMP_DIR"
rm -r ./* 2>/dev/null

# attempt to download the game

log_message "Game Nursery: Attempting to download $GAME_NAME"
display -i "$BG_IMG" -t "Now downloading $GAME_NAME!"
download_progress "$TMP_DIR/$ZIP_NAME" "$TARGET_SIZE_MEGA" &
download_pid=$!
if ! curl -s -k -L -o "$TMP_DIR/$ZIP_NAME" "$GAME_URL"; then
	kill $download_pid
	log_message "Game Nursery: Failed to download $GAME_NAME from $GAME_URL"
	display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to download $GAME_NAME from repository. Please try again later."
	exit 1
fi
kill $download_pid

# attempt to unzip the game

log_message "Game Nursery: Download successful. Attempting to extract $GAME_NAME"
display -i "$BG_IMG" -t "Now installing $GAME_NAME!"
cd "/mnt/SDCARD"
if ! 7zr x -y -scsUTF-8 "$TMP_DIR/$ZIP_NAME" >/dev/null 2>&1; then
	display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to extract latest game info files. Please try again later."
	rm -f "$TMP_DIR/$ZIP_NAME" >/dev/null 2>&1
	log_message "Game Nursery: Failed to extract $GAME_NAME from TMP_DIR/$ZIP_NAME"
	exit 1
else
	display -d 2 -i "$BG_IMG" -t "$GAME_NAME installed successfully!"
	log_message "Game Nursery: Extraction process completed successfully"
	rm -f "$TMP_DIR/$ZIP_NAME" 2>/dev/null
fi
