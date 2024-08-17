#!/bin/sh

echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness

SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"
FLAGS_DIR="${SDCARD_PATH}/.tmp_update/flags"
FIRST_BOOT_FLAG="${FLAGS_DIR}/first_boot_flag"
SCRIPTS_DIR="${SDCARD_PATH}/.tmp_update/scripts"

export SYSTEM_PATH="${SDCARD_PATH}/miyoo"
export PATH="$SYSTEM_PATH/app:${PATH}"
export LD_LIBRARY_PATH="$SYSTEM_PATH/lib:${LD_LIBRARY_PATH}"
export HOME="${SDCARD_PATH}"

mount -o bind "/mnt/SDCARD/.tmp_update/etc/profile" /etc/profile

THEME_JSON_FILE="/config/system.json"
USB_ICON_SOURCE="/mnt/SDCARD/Icons/Default/App/usb.png"
USB_ICON_DEST="/usr/miyoo/apps/usb_storage/usb_icon_80.png"

if [ -f "$THEME_JSON_FILE" ]; then
    THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
    THEME_PATH="${THEME_PATH%/}/"
    [ "${THEME_PATH: -1}" != "/" ] && THEME_PATH="${THEME_PATH}/"
    APP_THEME_ICON_PATH="${THEME_PATH}Icons/App/"
    if [ -f "${APP_THEME_ICON_PATH}usb.png" ]; then
        mount -o bind "${APP_THEME_ICON_PATH}usb.png" "$USB_ICON_DEST"
    else
        mount -o bind "$USB_ICON_SOURCE" "$USB_ICON_DEST"
    fi
fi

mkdir -p /mnt/SDCARD/themes
[ ! -d /mnt/SDCARD/themes/DONTTOUCH ] && cp -r /mnt/SDCARD/.tmp_update/res/DONTTOUCH /mnt/SDCARD/themes/

killprocess() {
    pid=$(ps | grep $1 | grep -v grep | cut -d' ' -f3)
    kill -9 $pid
}

runifnecessary() {
    a=$(ps | grep $1 | grep -v grep)
    [ "$a" == "" ] && $2 &
}

lcd_init 1
show "${SDCARD_PATH}/.tmp_update/res/installing.png" &

"${SCRIPTS_DIR}/firstboot.sh"

killall -9 show
swapon -p 40 "${SWAPFILE}"

# Run scripts for initial setup
/mnt/SDCARD/.tmp_update/scripts/syncthingstatus.sh
/mnt/SDCARD/.tmp_update/scripts/iconfresh.sh
/mnt/SDCARD/.tmp_update/scripts/sortfaves.sh
/mnt/SDCARD/.tmp_update/scripts/checkfaves.sh &

# Check WiFi status
wifi=$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')
[ "$wifi" -eq 0 ] && touch /tmp/wifioff && killall -9 wpa_supplicant && killall -9 udhcpc && rfkill || touch /tmp/wifion


# Auto launch
killall -9 main
sleep 5
killall -9 show

/mnt/SDCARD/.tmp_update/scripts/autoRA.sh
/mnt/SDCARD/.tmp_update/scripts/select.sh

while true; do
    runifnecessary "keymon" ${SYSTEM_PATH}/app/keymon
    cd ${SYSTEM_PATH}/app/
    ./MainUI
    [ -f /tmp/.cmdenc ] && /root/gameloader
    if [ -f /tmp/cmd_to_run.sh ]; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > /mnt/SDCARD/.tmp_update/.lastgame
        /tmp/cmd_to_run.sh
        rm /tmp/cmd_to_run.sh
        /mnt/SDCARD/.tmp_update/scripts/select.sh
    fi
done

