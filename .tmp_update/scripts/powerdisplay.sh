#!/bin/sh

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

for icon in ${BATTERY_ICONS}; do 
    TMP_OG_FILE="${THEME_PATH_SKIN}${icon}.png"
    if [ -f "$TMP_OG_FILE" ]; then
        TMP_BACKUP_FILE="${THEME_PATH_SKIN}${icon}-backup.png"
        if [ ! -f "$TMP_BACKUP_FILE" ]; then
            cp $TMP_OG_FILE $TMP_BACKUP_FILE
        fi
    fi
done
/mnt/SDCARD/.tmp_update/bin/battery_percent.elf $THEME_PATH_SKIN $CAPACITY