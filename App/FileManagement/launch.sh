#!/bin/sh
export HOME=`dirname "$0"`
export LD_LIBRARY_PATH=lib:$LD_LIBRARY_PATH

#THEME_JSON_FILE="/config/system.json"
#if [ ! -f "$THEME_JSON_FILE" ]; then
#    exit 1
#fi

#THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
#THEME_PATH="${THEME_PATH%/}/"

#if [ "${THEME_PATH: -1}" != "/" ]; then
#    THEME_PATH="${THEME_PATH}/"
#fi

# set stick to d-pad mode
killall -q -USR2 joystickinput

cd $HOME
./DinguxCommander #--res-dir ${THEME_PATH} || ./DinguxCommander --res-dir /mnt/SDCARD/Themes/SPRUCE
sync

# set stick to d-pad mode
killall -q -USR2 joystickinput

auto_regen_tmp_update