#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

encoded_name="$1"
theme_name=$(echo "$encoded_name" | sed 's/%20/ /g' | sed "s/%27/'/g")

THEME_BASE_URL="https://raw.githubusercontent.com/spruceUI/PyUI-Themes/main/PackedThemes"
ARCHIVE_DIR=/mnt/SDCARD/spruce/archives
TMP_DIR="/mnt/SDCARD/App/ThemeGarden/tmp"

theme_url="${THEME_BASE_URL}/${encoded_name}.7z"
temp_path="$TMP_DIR/${theme_name}.7z"
final_path="$ARCHIVE_DIR/preMenu/${theme_name}.7z"

start_pyui_message_writer
log_and_display_message "Now downloading $theme_name!"

TARGET_SIZE_BYTES="$(get_remote_filesize_bytes "$theme_url")"
TARGET_SIZE_KILO=$((TARGET_SIZE_BYTES / 1024))
TARGET_SIZE_MEGA=$((TARGET_SIZE_KILO / 1024))
REQUIRED_SPACE=$((TARGET_SIZE_MEGA * 3))
if [ "$REQUIRED_SPACE" -lt 3 ]; then
    REQUIRED_SPACE=3
fi
AVAILABLE_SPACE="$(df -m "/mnt/SDCARD" | awk 'NR==2{print $4}')"

log_message "Theme Garden: $AVAILABLE_SPACE MiB available; $REQUIRED_SPACE MiB required to install $theme_name"
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
	log_and_display_message "You need at least $REQUIRED_SPACE MiB free to install $theme_name. Please free up some space and try again later."
    sleep 4
	exit 1
else
	log_message "Theme Garden: Available space is sufficient. Proceeding to download $theme_name"
fi

# initialize temporary theme directory

mkdir "$TMP_DIR" 2>/dev/null
cd "$TMP_DIR"
rm -rf "$TMP_DIR"/* 2>/dev/null

# attempt to download the theme

log_and_display_message "Now downloading $theme_name!"
if ! download_and_display_progress "$theme_url" "$temp_path" "$theme_name" "$TARGET_SIZE_BYTES"; then
	exit 1
else
	log_and_display_message "Successfully downloaded $theme_name!"
	sleep 2
fi

mkdir -p "$ARCHIVE_DIR/preMenu"
mv "$temp_path" "$final_path"
