#!/bin/sh

IMAGE_PATH="/mnt/SDCARD/spruce/imgs/refreshing.png"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Add silent mode flag
silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1

# Only show image if not in silent mode
if [ $silent_mode -eq 0 ]; then
    display -p bottom -t "Refreshing icons... please wait......" --icon "/mnt/SDCARD/Themes/SPRUCE/App/iconfresh.png"
fi

EMULATOR_BASE_PATH="/mnt/SDCARD/Emu/"
APP_BASE_PATH="/mnt/SDCARD/app/"
THEME_JSON_FILE="/config/system.json"
SKIN_PATH="/mnt/SDCARD/miyoo/res/skin"
DEFAULT_SKIN_PATH="/mnt/SDCARD/Icons/Default/skin"

if [ ! -f "$THEME_JSON_FILE" ]; then
    exit 1
fi

THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
THEME_PATH="${THEME_PATH%/}/"

if [ "${THEME_PATH: -1}" != "/" ]; then
    THEME_PATH="${THEME_PATH}/"
fi

DEFAULT_ICON_PATH="/mnt/SDCARD/icons/default/"
DEFAULT_ICON_SEL_PATH="${DEFAULT_ICON_PATH}sel/"
APP_DEFAULT_ICON_PATH="/mnt/SDCARD/Icons/Default/App/"
APP_THEME_ICON_PATH="${THEME_PATH}Icons/App/"

update_emulator_icons() {
    local CONFIG_FILE=$1

    OLD_ICON_PATH=$(awk -F'"' '/"icon":/ {print $4}' "$CONFIG_FILE")
    OLD_ICON_SEL_PATH=$(awk -F'"' '/"iconsel":/ {print $4}' "$CONFIG_FILE")

    ICON_FILE_NAME=$(basename "$OLD_ICON_PATH")
    ICON_SEL_FILE_NAME=$(basename "$OLD_ICON_SEL_PATH")

    THEME_ICON_PATH="${THEME_PATH}icons/${ICON_FILE_NAME}"
    THEME_ICON_SEL_PATH="${THEME_PATH}icons/sel/${ICON_SEL_FILE_NAME}"

    if [ -f "$THEME_ICON_PATH" ]; then
        NEW_ICON_PATH="$THEME_ICON_PATH"
    else
        NEW_ICON_PATH="${DEFAULT_ICON_PATH}${ICON_FILE_NAME}"
    fi

    if [ -f "$THEME_ICON_SEL_PATH" ]; then
        NEW_ICON_SEL_PATH="$THEME_ICON_SEL_PATH"
    else
        NEW_ICON_SEL_PATH="${DEFAULT_ICON_PATH}${ICON_SEL_FILE_NAME}"
    fi

    sed -i "s|${OLD_ICON_PATH}|${NEW_ICON_PATH}|g" "$CONFIG_FILE"
    sed -i "s|${OLD_ICON_SEL_PATH}|${NEW_ICON_SEL_PATH}|g" "$CONFIG_FILE"
}

update_app_icons() {
    local CONFIG_FILE=$1

    OLD_ICON_PATH=$(awk -F'"' '/"icon":/ {print $4}' "$CONFIG_FILE")
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

find "$EMULATOR_BASE_PATH" -name "config.json" | while read CONFIG_FILE; do
    update_emulator_icons "$CONFIG_FILE"
done

find "$APP_BASE_PATH" -name "config.json" | while read CONFIG_FILE; do
    update_app_icons "$CONFIG_FILE"
done

# Removed the update_skin_images function and its call

# Only kill images if not in silent mode
if [ $silent_mode -eq 0 ]; then
    display_kill
fi

/mnt/SDCARD/spruce/scripts/powerdisplay.sh