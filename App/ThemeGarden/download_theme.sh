#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

theme_name="$1"

THEME_BASE_URL="https://raw.githubusercontent.com/spruceUI/PyUI-Themes/main/PackedThemes"
ARCHIVE_DIR=/mnt/SDCARD/spruce/archives
TMP_DIR="/mnt/SDCARD/App/ThemeGarden/tmp"

encoded_name=$(echo "$theme_name" | sed 's/ /%20/g' | sed "s/'/%27/g")
theme_url="${THEME_BASE_URL}/${encoded_name}.7z"
temp_path="$TMP_DIR/${theme_name}.7z"
final_path="$ARCHIVE_DIR/preMenu/${theme_name}.7z"

start_pyui_message_writer
log_and_display_message "Now downloading $theme_name!"

TARGET_SIZE_BYTES="$(wget --spider --server-response --no-check-certificate "$theme_url" 2>&1 | grep -i 'Content-Length' | tail -n1 | awk '{print $2}' | tr -d '\r\n')"
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
if ! wget --quiet --no-check-certificate --output-document="$temp_path" "$theme_url"; then
	log_and_display_message "Unable to download $theme_name from repository. Please try again later."
    sleep 4
	rm -f "$temp_path"
	exit 1
fi

mkdir -p "$ARCHIVE_DIR/preMenu"
mv "$temp_path" "$final_path"
