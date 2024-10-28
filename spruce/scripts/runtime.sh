#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh
rotate_logs

# Resetting log file location
log_file="/mnt/SDCARD/Saves/spruce/spruce.log"

cores_online &
echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger
echo L,L2,R,R2,X,A,B,Y > /sys/module/gpio_keys_polled/parameters/button_config
SETTINGS_FILE="/config/system.json"
SWAPFILE="/mnt/SDCARD/cachefile"
SDCARD_PATH="/mnt/SDCARD"
SCRIPTS_DIR="${SDCARD_PATH}/spruce/scripts"
BIN_DIR="${SDCARD_PATH}/spruce/bin"

export SYSTEM_PATH="${SDCARD_PATH}/miyoo"
export PATH="$SYSTEM_PATH/app:${PATH}"
export LD_LIBRARY_PATH="$SYSTEM_PATH/lib:${LD_LIBRARY_PATH}"
export HOME="${SDCARD_PATH}"
export HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

# Create directories and mount in parallel
(
    mkdir -p /var/lib/alsa
    mount -o bind "/mnt/SDCARD/miyoo/var/lib" /var/lib &
    mount -o bind /mnt/SDCARD/miyoo/app /usr/miyoo/app &
    mount -o bind /mnt/SDCARD/miyoo/lib /usr/miyoo/lib &
    mount -o bind /mnt/SDCARD/miyoo/res /usr/miyoo/res &
    mount -o bind "/mnt/SDCARD/miyoo/etc/profile" /etc/profile &
    wait
)

lcd_init 1

# Stop NTPD
nice -n -18 sh -c '/etc/init.d/sysntpd stop && /etc/init.d/ntpd stop' > /dev/null 2>&1 &

# Flag cleanup
flag_remove "themeChanged"
flag_remove "log_verbose"
flag_remove "low_battery"
flag_remove "in_menu"

log_message " " -v
log_message "---------Starting up---------"
log_message " " -v

# import multipass.cfg and start watchdog for new network additions via MainUI
nice -n 15 ${SCRIPTS_DIR}/wpa_watchdog.sh > /dev/null &

# Check if WiFi is enabled
wifi=$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')
if [ "$wifi" -eq 0 ]; then
    touch /tmp/wifioff && killall -9 wpa_supplicant && killall -9 udhcpc && rfkill
    log_message "WiFi turned off"
else
    touch /tmp/wifion
    log_message "WiFi turned on"
fi

killall -9 main ### SUPER important in preventing .tmp_update suicide

# Bring up network and services
${SCRIPTS_DIR}/wifi_watchdog.sh > /dev/null &

# Check for first_boot flag and run ThemeUnpacker accordingly
if flag_check "first_boot"; then
    ${SCRIPTS_DIR}/ThemeUnpacker.sh --silent &
    log_message "ThemeUnpacker started silently in background due to firstBoot flag"
else
    ${SCRIPTS_DIR}/ThemeUnpacker.sh
fi

${SCRIPTS_DIR}/emufresh_md5_multi.sh &

alsactl nrestore &

# Restore and monitor brightness
if [ -f "/mnt/SDCARD/spruce/settings/sys_brightness_level" ]; then
    BRIGHTNESS=$(cat /mnt/SDCARD/spruce/settings/sys_brightness_level)
    # only set non zero brightness value
    if [ $BRIGHTNESS -ne 0 ]; then 
        echo ${BRIGHTNESS} > /sys/devices/virtual/disp/disp/attr/lcdbl
    fi
fi
${SCRIPTS_DIR}/brightness_watchdog.sh > /dev/null &

# ensure keymon is running first and only listen to event0 for power button & event3 for keyboard events
# keymon /dev/input/event0 &
keymon /dev/input/event3 &
${SCRIPTS_DIR}/powerbutton_watchdog.sh &

# rename ttyS0 to ttyS2 so that PPSSPP cannot read the joystick raw data
mv /dev/ttyS0 /dev/ttyS2

# create virtual joypad from keyboard input, it should create /dev/input/event4 system file
cd ${BIN_DIR}
./joypad /dev/input/event3 &

# read joystick raw data from serial input and apply calibration,
# then send analog input to /dev/input/event4 when in ANALOG_MODE (this is default)
# and send keyboard input to /dev/input/event3 when in KEYBOARD_MODE.
# Please send kill signal USR1 to switch to ANALOG_MODE
# and send kill signal USR2 to switch to KEYBOARD_MODE
${SCRIPTS_DIR}/autoReloadCalibration.sh &

# run game switcher watchdog before auto load game is loaded
${SCRIPTS_DIR}/gameswitcher_watchdog.sh &

check_and_handle_firmware_app &

check_and_hide_update_app &

# Load idle monitors before game resume or MainUI
${SCRIPTS_DIR}/applySetting/idlemon_mm.sh &

# check whether to auto-resume into a game
if flag_check "save_active"; then
    ${SCRIPTS_DIR}/autoRA.sh  &> /dev/null
    log_message "Auto Resume executed"
else
	log_message "Auto Resume skipped (no save_active flag)"
fi

${SCRIPTS_DIR}/spruceRestoreShow.sh &
${SCRIPTS_DIR}/autoIconRefresh.sh &

# check whether to run first boot procedure
if flag_check "first_boot"; then
    "${SCRIPTS_DIR}/firstboot.sh"
else
    log_message "First boot procedures skipped"
fi

log_precise "Starting swap file activation"
swapon -p 40 "${SWAPFILE}"
log_precise "Swap file activated"

# Run scripts for initial setup
#${SCRIPTS_DIR}/forcedisplay.sh
${SCRIPTS_DIR}/low_power_warning.sh
${SCRIPTS_DIR}/ffplay_is_now_media.sh &
${SCRIPTS_DIR}/checkfaves.sh &
${SCRIPTS_DIR}/credits_watchdog.sh &

# Initialize CPU settings
set_smart

# start main loop
log_message "Starting main loop"
${SCRIPTS_DIR}/principal.sh