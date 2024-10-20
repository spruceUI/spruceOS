#!/bin/sh

echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger
echo L,L2,R,R2,X,A,B,Y > /sys/module/gpio_keys_polled/parameters/button_config
SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"
SCRIPTS_DIR="${SDCARD_PATH}/.tmp_update/scripts"
NEW_SCRIPTS_DIR="${SDCARD_PATH}/spruce/scripts"

export SYSTEM_PATH="${SDCARD_PATH}/miyoo"
export PATH="$SYSTEM_PATH/app:${PATH}"
export LD_LIBRARY_PATH="$SYSTEM_PATH/lib:${LD_LIBRARY_PATH}"
export HOME="${SDCARD_PATH}"
export HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

mkdir /var/lib /var/lib/alsa ### We create the directories that by default are not included in the system.
mount -o bind "/mnt/SDCARD/.tmp_update/lib" /var/lib ###We mount the folder that includes the alsa configuration, just as the system should include it.
mount -o bind /mnt/SDCARD/miyoo/app /usr/miyoo/app
mount -o bind /mnt/SDCARD/miyoo/lib /usr/miyoo/lib
mount -o bind /mnt/SDCARD/miyoo/res /usr/miyoo/res
mount -o bind "/mnt/SDCARD/.tmp_update/etc/profile" /etc/profile

# Stop NTPD
/etc/init.d/sysntpd stop
/etc/init.d/ntpd stop

# Load helper functions and helpers
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
#. /mnt/SDCARS/spruce/scripts/runtimeHelper.sh
#. /mnt/SDCARD/spruce/bin/SSH/dropbearFunctions.sh
#. /mnt/SDCARD/spruce/bin/Samba/sambaFunctions.sh
#. /mnt/SDCARD/App/WifiFileTransfer/sftpgoFunctions.sh
#. /mnt/SDCARD/App/Syncthing/syncthingFunctions.sh
#rotate_logs &

# Flag cleanup
flag_remove "themeChanged"
flag_remove "log_verbose"
flag_remove "low_battery"
flag_remove "in_menu"

log_message " "
log_message "---------Starting up---------"
log_message " "

# Generate wpa_supplicant.conf from wifi.cfg if available
${NEW_SCRIPTS_DIR}/multipass.sh

# Check if WiFi is enabled
wifi=$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')
if [ "$wifi" -eq 0 ]; then
    touch /tmp/wifioff && killall -9 wpa_supplicant && killall -9 udhcpc && rfkill
    log_message "WiFi turned off"
else
    touch /tmp/wifion
    log_message "WiFi turned on"
fi

killall -9 main
kill_images

# Bring up network services
nice -n 15 /mnt/SDCARD/.tmp_update/scripts/networkservices.sh &

${NEW_SCRIPTS_DIR}/spruceRestoreShow.sh &

# Check for first_boot flag and run ThemeUnpacker accordingly
if flag_check "first_boot"; then
    ${NEW_SCRIPTS_DIR}/ThemeUnpacker.sh --silent &
    log_message "ThemeUnpacker started silently in background due to firstBoot flag"
else
    ${NEW_SCRIPTS_DIR}/ThemeUnpacker.sh
fi

# Checks if quick-resume is active and runs it if not returns to this point.
alsactl nrestore ###We tell the sound driver to load the configuration.
log_message "ALSA configuration loaded"

# ensure keymon is running first and only listen to event0 for power button & event3 for keyboard events
# keymon /dev/input/event0 &
keymon /dev/input/event3 &
${NEW_SCRIPTS_DIR}/powerbutton_watchdog.sh &

# rename ttyS0 to ttyS2, therefore PPSSPP cannot read the joystick raw data
mv /dev/ttyS0 /dev/ttyS2
# create virtual joypad from keyboard input, it should create /dev/input/event4 system file
cd /mnt/SDCARD/.tmp_update/bin
./joypad /dev/input/event3 &
# wait long enough for creating virtual joypad
sleep 0.3
# read joystick raw data from serial input and apply calibration,
# then send to /dev/input/event4
( ./joystickinput /dev/ttyS2 /config/joypad.config | ./sendevent /dev/input/event4 ) &
        
# run game switcher watchdog before auto load game is loaded
/mnt/SDCARD/.tmp_update/scripts/gameswitcher_watchdog.sh &

# unhide -FirmwareUpdate- App only if necessary
VERSION="$(cat /usr/miyoo/version)"
if [ "$VERSION" -lt 20240713100458 ]; then
    sed -i 's|"#label":|"label":|' "/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
    log_message "Detected firmware version $VERSION; enabling -FirmwareUpdate- app"
fi

${NEW_SCRIPTS_DIR}/autoRA.sh  &> /dev/null
log_message "Auto Resume executed"

${NEW_SCRIPTS_DIR}/autoIconRefresh.sh &

lcd_init 1

"${NEW_SCRIPTS_DIR}/firstboot.sh"
log_message "First boot script executed"

swapon -p 40 "${SWAPFILE}"
log_message "Swap file activated"

# Run scripts for initial setup
#${NEW_SCRIPTS_DIR}/forcedisplay.sh
${NEW_SCRIPTS_DIR}/low_power_warning.sh
${NEW_SCRIPTS_DIR}/ffplay_is_now_media.sh
${NEW_SCRIPTS_DIR}/checkfaves.sh &
${NEW_SCRIPTS_DIR}/credits_watchdog.sh &
${NEW_SCRIPTS_DIR}/applySetting/idlemon_mm.sh
log_message "Initial setup scripts executed"
kill_images

# Initialize CPU settings
set_smart

# start main loop
log_message "Starting main loop"
${NEW_SCRIPTS_DIR}/principal.sh