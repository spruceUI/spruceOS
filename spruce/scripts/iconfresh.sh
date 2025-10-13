#!/bin/sh

ICONFRESH_ICON="/mnt/SDCARD/spruce/imgs/iconfresh.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


if [ "$PLATFORM" = "Flip" ] || [ "$PLATFORM" = "Brick" ]; then
	# Function to extract the current theme path
	get_theme_path() {
		awk -F'"' '/"theme":/ {print $4}' "$SYSTEM_JSON" | sed 's:/*$::'
	}

	# Get the theme path
	THEME_PATH=$(get_theme_path)

	# Check if THEME_PATH is valid
	if [ -z "$THEME_PATH" ]; then
		echo "Error: Could not determine theme path from $SYSTEM_JSON"
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


else

	# Add silent mode flag
	silent_mode=0
	[ "$1" = "--silent" ] && silent_mode=1

	# Only show image if not in silent mode
	if [ $silent_mode -eq 0 ]; then
		display --icon "$ICONFRESH_ICON" -t "Refreshing icons... please wait......"
	fi

	EMULATOR_BASE_PATH="/mnt/SDCARD/Emu/"
	APP_BASE_PATH="/mnt/SDCARD/App/"

	case "$PLATFORM" in
		"A30" )
			SKIN_PATH="/mnt/SDCARD/miyoo/res/skin" 
			ICONS="icons"
			;;
		"Flip" )
			SKIN_PATH="/mnt/SDCARD/miyoo355/app/skin"
			ICONS="icons"
			;;
		"Brick" )
			SKIN_PATH="/mnt/SDCARD/Themes/SPRUCE/skin" 
			ICONS="icontop"
			;;
			
		"SmartPro" )
			SKIN_PATH="/mnt/SDCARD/Themes/SPRUCE/skin"
			ICONS="icontop"
			;;
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

	DEFAULT_ICON_PATH="/mnt/SDCARD/Icons/Default/"
	DEFAULT_ICON_SEL_PATH="${DEFAULT_ICON_PATH}sel/"
	APP_DEFAULT_ICON_PATH="/mnt/SDCARD/Icons/Default/app/"
	APP_THEME_ICON_PATH="${THEME_PATH}${ICONS}/app/"

	update_emulator_icons() {
		local CONFIG_FILE=$1

	if [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
		OLD_ICON_PATH=$(awk -F'"' '/"icontop":/ {print $4}' "$CONFIG_FILE")
	else
		OLD_ICON_PATH=$(awk -F'"' '/"icon":/ {print $4}' "$CONFIG_FILE")
	fi
		OLD_ICON_SEL_PATH=$(awk -F'"' '/"iconsel":/ {print $4}' "$CONFIG_FILE")

		ICON_FILE_NAME=$(basename "$OLD_ICON_PATH")
		ICON_SEL_FILE_NAME=$(basename "$OLD_ICON_SEL_PATH")

		THEME_ICON_PATH="${THEME_PATH}${ICONS}/${ICON_FILE_NAME}"
		THEME_ICON_SEL_PATH="${THEME_PATH}${ICONS}/sel/${ICON_SEL_FILE_NAME}"

		if [ -f "$THEME_ICON_PATH" ]; then
			NEW_ICON_PATH="$THEME_ICON_PATH"
		else
			NEW_ICON_PATH="${DEFAULT_ICON_PATH}${ICON_FILE_NAME}"
		fi

		if [ -f "$THEME_ICON_SEL_PATH" ]; then
			NEW_ICON_SEL_PATH="$THEME_ICON_SEL_PATH"
		else
			NEW_ICON_SEL_PATH="${DEFAULT_ICON_SEL_PATH}${ICON_SEL_FILE_NAME}"
		fi

		sed -i "s|${OLD_ICON_PATH}|${NEW_ICON_PATH}|g" "$CONFIG_FILE"
		sed -i "s|${OLD_ICON_SEL_PATH}|${NEW_ICON_SEL_PATH}|g" "$CONFIG_FILE"
	}

	update_app_icons() {
		local CONFIG_FILE=$1

	if [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
		OLD_ICON_PATH=$(awk -F'"' '/"icontop":/ {print $4}' "$CONFIG_FILE")
	else
		OLD_ICON_PATH=$(awk -F'"' '/"icon":/ {print $4}' "$CONFIG_FILE")
	fi
		ICON_FILE_NAME=$(basename "$OLD_ICON_PATH")

		THEME_APP_ICON_PATH="${APP_THEME_ICON_PATH}${ICON_FILE_NAME}"
		DEFAULT_APP_ICON_PATH="${APP_DEFAULT_ICON_PATH}${ICON_FILE_NAME}"

		if [ -f "$THEME_APP_ICON_PATH" ]; then
			NEW_ICON_PATH="$THEME_APP_ICON_PATH"
		else
			NEW_ICON_PATH="$DEFAULT_APP_ICON_PATH"
		fi

		sed -i "s|$OLD_ICON_PATH|$NEW_ICON_PATH|g" "$CONFIG_FILE"
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

	find "$EMULATOR_BASE_PATH" -name "config.json" | while read CONFIG_FILE; do
		update_emulator_icons "$CONFIG_FILE"
	done

	find "$APP_BASE_PATH" -name "config.json" | while read CONFIG_FILE; do
		update_app_icons "$CONFIG_FILE"
	done

	update_skin_images

	/mnt/SDCARD/spruce/scripts/powerdisplay.sh

	# Only kill images if not in silent mode
	if [ $silent_mode -eq 0 ]; then
		display_kill
	fi
fi
