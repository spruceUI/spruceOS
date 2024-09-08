#!/bin/sh

echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger
echo L,L2,R,R2,X,A,B,Y > /sys/module/gpio_keys_polled/parameters/button_config
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

mkdir /var/lib /var/lib/alsa ### We create the directories that by default are not included in the system.
mount -o bind "/mnt/SDCARD/.tmp_update/lib" /var/lib ###We mount the folder that includes the alsa configuration, just as the system should include it.
mount -o bind /mnt/SDCARD/miyoo/ /usr/miyoo/
mount -o bind "/mnt/SDCARD/.tmp_update/etc/profile" /etc/profile

wifi=$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')
[ "$wifi" -eq 0 ] && touch /tmp/wifioff && killall -9 wpa_supplicant && killall -9 udhcpc && rfkill || touch /tmp/wifion
killall -9 main
# Checks if quick-resume is active and runs it if not returns to this point.
alsactl nrestore ###We tell the sound driver to load the configuration.
/mnt/SDCARD/.tmp_update/scripts/autoRA.sh  &> /dev/null


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


# killprocess() {
#     pid=$(ps | grep $1 | grep -v grep | cut -d' ' -f3)
#     kill -9 $pid
# }

# runifnecessary() {
#     a=$(ps | grep $1 | grep -v grep)
#     [ "$a" == "" ] && $2 &
# }




lcd_init 1
show "${SDCARD_PATH}/.tmp_update/res/installing.png" &

"${SCRIPTS_DIR}/firstboot.sh"

killall -9 show
swapon -p 40 "${SWAPFILE}"



# Run scripts for initial setup
/mnt/SDCARD/.tmp_update/scripts/syncthingstatus.sh
/mnt/SDCARD/.tmp_update/scripts/sftpgo.sh
/mnt/SDCARD/.tmp_update/scripts/sortfaves.sh
/mnt/SDCARD/.tmp_update/scripts/forcedisplay.sh
/mnt/SDCARD/.tmp_update/scripts/low_power_warning.sh
/mnt/SDCARD/.tmp_update/scripts/ledcontrol.sh
/mnt/SDCARD/.tmp_update/scripts/checkfaves.sh &



killall -9 show




# start main loop
/mnt/SDCARD/.tmp_update/scripts/principal.sh
