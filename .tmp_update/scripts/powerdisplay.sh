#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BATTERY_PERCENT="/mnt/SDCARD/.tmp_update/bin/battery_percent.elf"
THEME_JSON_FILE="/config/system.json"
CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
BATTERY_ICONS="ic-power-charge-0% \
ic-power-charge-25% \
ic-power-charge-50% \
ic-power-charge-75% \
ic-power-charge-100% \
power-0%-icon \
power-20%-icon \
power-50%-icon \
power-80%-icon \
power-full-icon"

if [ ! -f "$THEME_JSON_FILE" ]; then
    exit 1
fi

THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
THEME_PATH="${THEME_PATH%/}/"

if [ "${THEME_PATH: -1}" != "/" ]; then
    THEME_PATH="${THEME_PATH}/"
fi

THEME_PATH_SKIN="${THEME_PATH}skin/"

if ! flag_check "show_battery_percent"; then
    log_message "Cleaning battery icons" -v 
    $BATTERY_PERCENT "${THEME_PATH_SKIN}" " "
    exit 1
fi

for icon in ${BATTERY_ICONS}; do 
    TMP_OG_FILE="${THEME_PATH_SKIN}${icon}.png"
    if [ -f "$TMP_OG_FILE" ]; then
        TMP_BACKUP_FILE="${THEME_PATH_SKIN}${icon}-backup.png"
        if [ ! -f "$TMP_BACKUP_FILE" ]; then
            cp "${TMP_OG_FILE}" "${TMP_BACKUP_FILE}" 
        fi
    fi
done

THEME_PATH_CONFIG="${THEME_PATH}config.json"

PATH_FONT=$(jq -r '.batteryPercentage.font' "${THEME_PATH_CONFIG}" )
if [[ -z "$PATH_FONT" ]]; then
    PATH_FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"
else
    PATH_FONT="${THEME_PATH}${PATH_FONT}"
fi
SIZE_FONT=$(jq -r '.batteryPercentage.size' "${THEME_PATH_CONFIG}" )
if [[ -z "$SIZE_FONT" ]]; then
    SIZE_FONT="20"
fi
COLOR_FONT=$(jq -r '.batteryPercentage.color' "${THEME_PATH_CONFIG}" )
if [[ -z "$COLOR_FONT" ]]; then
    COLOR_FONT="#FFFFFF"
fi

log_message "Applying battery percent to icons" -v 
$BATTERY_PERCENT "${THEME_PATH_SKIN}" $CAPACITY "${PATH_FONT}" "${SIZE_FONT}" "${COLOR_FONT}" 
