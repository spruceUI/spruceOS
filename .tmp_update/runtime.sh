#!/bin/sh

#echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger
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
export HELPER_FUNCTIONS="/mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh"

mkdir /var/lib /var/lib/alsa ### We create the directories that by default are not included in the system.
mount -o bind "/mnt/SDCARD/.tmp_update/lib" /var/lib ###We mount the folder that includes the alsa configuration, just as the system should include it.
mount -o bind /mnt/SDCARD/miyoo/app /usr/miyoo/app
mount -o bind /mnt/SDCARD/miyoo/lib /usr/miyoo/lib
mount -o bind /mnt/SDCARD/miyoo/res /usr/miyoo/res
mount -o bind "/mnt/SDCARD/.tmp_update/etc/profile" /etc/profile

# Load helper functions and helpers
. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

log_message " "
log_message "---------Starting up---------"
log_message " "
# Ensure the spruce folder exists
spruce_folder="/mnt/SDCARD/Saves/spruce"
if [ ! -d "$spruce_folder" ]; then
    mkdir -p "$spruce_folder"
    log_message "Created spruce folder at $spruce_folder"
fi

# Check if WiFi is enabled
wifi=$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')
if [ "$wifi" -eq 0 ]; then
    touch /tmp/wifioff && killall -9 wpa_supplicant && killall -9 udhcpc && rfkill
    log_message "WiFi turned off"
else
    touch /tmp/wifion
    log_message "WiFi turned on"
fi
kill_images
# Syncthing Insertion Here (Do not remove)

# Checks if quick-resume is active and runs it if not returns to this point.
alsactl nrestore ###We tell the sound driver to load the configuration.
log_message "ALSA configuration loaded"

/mnt/SDCARD/.tmp_update/scripts/autoRA.sh  &> /dev/null
log_message "Auto Resume executed"


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
show_image "${SDCARD_PATH}/.tmp_update/res/installing.png"

"${SCRIPTS_DIR}/firstboot.sh"
log_message "First boot script executed"

kill_images
swapon -p 40 "${SWAPFILE}"
log_message "Swap file activated"

# Run scripts for initial setup
/mnt/SDCARD/.tmp_update/scripts/syncthingstatus.sh
/mnt/SDCARD/.tmp_update/scripts/sftpgo.sh
/mnt/SDCARD/.tmp_update/scripts/sortfaves.sh
/mnt/SDCARD/.tmp_update/scripts/forcedisplay.sh
/mnt/SDCARD/.tmp_update/scripts/low_power_warning.sh
/mnt/SDCARD/.tmp_update/scripts/checkfaves.sh &
log_message "Initial setup scripts executed"
kill_images


# start main loop
log_message "Starting main loop"
/mnt/SDCARD/.tmp_update/scripts/principal.sh

