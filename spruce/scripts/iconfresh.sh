#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

get_theme_path() {
	jq -r '.theme' "$SYSTEM_JSON"
}

update_skin_images() {
	local ALL_IMAGES_PRESENT=true
	# List of images to check
	IMAGES_LIST="app_loading_01.png app_loading_02.png app_loading_03.png app_loading_04.png app_loading_05.png app_loading_bg.png"
	for IMAGE_NAME in $IMAGES_LIST; do
		THEME_IMAGE_PATH="${THEME_PATH}skin/${IMAGE_NAME}"
		DEFAULT_IMAGE_PATH="${SKIN_PATH}/${IMAGE_NAME}"
		FALLBACK_IMAGE_PATH="${DEFAULT_SKIN_PATH}/${IMAGE_NAME}"
		if [ ! -f "$THEME_IMAGE_PATH" ]; then
			ALL_IMAGES_PRESENT=false
			break
		fi
	done
	if [ "$ALL_IMAGES_PRESENT" = true ]; then
		for IMAGE_NAME in $IMAGES_LIST; do
			THEME_IMAGE_PATH="${THEME_PATH}skin/${IMAGE_NAME}"
			DEFAULT_IMAGE_PATH="${SKIN_PATH}/${IMAGE_NAME}"
			cp "$THEME_IMAGE_PATH" "$DEFAULT_IMAGE_PATH"
			log_message "Updated $DEFAULT_IMAGE_PATH with $THEME_IMAGE_PATH"
		done
	else
		for IMAGE_NAME in $IMAGES_LIST; do
			FALLBACK_IMAGE_PATH="${DEFAULT_SKIN_PATH}/${IMAGE_NAME}"
			DEST_IMAGE_PATH="${SKIN_PATH}/${IMAGE_NAME}"
			if [ -f "$FALLBACK_IMAGE_PATH" ]; then
				cp "$FALLBACK_IMAGE_PATH" "$DEST_IMAGE_PATH"
				log_message "Used fallback image $FALLBACK_IMAGE_PATH for $DEST_IMAGE_PATH"
			else
				log_message "Fallback image not found: $FALLBACK_IMAGE_PATH"
			fi
		done
	fi
}

if [ "$PLATFORM" = "Flip" ] || [ "$PLATFORM" = "Brick" ]; then

	THEME_PATH=$(get_theme_path)

	# Check if THEME_PATH is valid
	if [ -z "$THEME_PATH" ] || [ "$THEME_PATH" = "null" ]; then
		log_message "Error: Could not determine theme path from $SYSTEM_JSON"
		exit 1
	fi

	# Paths
	THEME_SRC="/mnt/SDCARD/Themes/${THEME_PATH}/skin"
	DEFAULT_SRC="/mnt/SDCARD/miyoo355/app/skin"
	CFG="/mnt/SDCARD/Themes/${THEME_PATH}/config.json"
	DST="/usr/miyoo/bin/skin"

	# Determine which source to mount
	if [ -f "$CFG" ]; then
		BIND_ENABLED=$(jq -r '.["bindOverMiyooTheme"] // false' "$CFG")
	else
		BIND_ENABLED="false"
	fi

	if [ "$BIND_ENABLED" = "true" ]; then
		SRC="$THEME_SRC"
		echo "Theme '$THEME_PATH' enables bind-over-miyoo-theme — mounting theme skin."
	else
		SRC="$DEFAULT_SRC"
		echo "Theme '$THEME_PATH' disables bind-over-miyoo-theme — mounting default skin."
	fi

	# Unmount if already mounted
	if mountpoint -q "$DST"; then
		echo "Unmounting existing bind at $DST..."
		umount "$DST"
	fi

	# Perform the bind mount
	echo "Mounting $SRC to $DST..."
	mount --bind "$SRC" "$DST"

	# Verify
	if mountpoint -q "$DST"; then
		echo "Successfully mounted: $SRC -> $DST"
	else
		echo "Error: Failed to mount $SRC to $DST"
		exit 1
	fi

elif [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "SmartPro" ]; then

	case "$PLATFORM" in
		"A30" )	SKIN_PATH="/mnt/SDCARD/miyoo/res/skin" ;;
		"SmartPro" ) SKIN_PATH="/mnt/SDCARD/Themes/SPRUCE/skin"	;;
	esac
	
	DEFAULT_SKIN_PATH="/mnt/SDCARD/Icons/Default/skin"

	if [ ! -f "$SYSTEM_JSON" ]; then
		exit 1
	fi

	THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$SYSTEM_JSON")
	THEME_PATH="${THEME_PATH%/}/"

	if [ "${THEME_PATH: -1}" != "/" ]; then
		THEME_PATH="${THEME_PATH}/"
	fi

	update_skin_images
fi
