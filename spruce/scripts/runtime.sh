#!/bin/sh

# mnt "/mnt/SDCARD/spruce/scripts/whte_rbt.obj"
# >access security
# access: PERMISSION DENIED.
# >access security grid
# access: PERMISSION DENIED.
# >access main security grid
# access: PERMISSION DENIED.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

rotate_logs
log_file="/mnt/SDCARD/Saves/spruce/spruce.log" # Resetting log file location
log_message "---------Starting up---------"

export HOME="/mnt/SDCARD"
SCRIPTS_DIR="/mnt/SDCARD/spruce/scripts"
TMP_BACKLIGHT_PATH=/mnt/SDCARD/Saves/spruce/tmp_backlight
TMP_VOLUME_PATH=/mnt/SDCARD/Saves/spruce/tmp_volume

cores_online
set_performance

case "$PLATFORM" in
    "A30"|"Flip") echo mmc0 > "$LED_PATH"/trigger ;;
esac

if flag_check "reboot-update"; then
    log_message "Updater continuing!"
    /mnt/SDCARD/App/-Updater/updater.sh
fi

runtime_mounts_$PLATFORM

if [ "$PLATFORM" = "A30" ]; then
    echo L,L2,R,R2,X,A,B,Y > /sys/module/gpio_keys_polled/parameters/button_config
    nice -n -18 sh -c '/etc/init.d/sysntpd stop && /etc/init.d/ntpd stop' > /dev/null 2>&1 &  # Stop NTPD

    # Check if WiFi is enabled
    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
        touch /tmp/wifioff && killall -9 wpa_supplicant && killall -9 udhcpc && rfkill
        log_message "WiFi turned off"
    else
        touch /tmp/wifion
        log_message "WiFi turned on"
    fi

    killall -9 main ### SUPER important in preventing .tmp_update suicide

# elif [ "$PLATFORM" = "Flip" ]; then
#	log_message "Checking for payload updates"
#	"$SCRIPTS_DIR"/update_miyoo_payload.sh
fi

export PATH="$SYSTEM_PATH/app:${PATH}"

# Flag cleanup
flag_remove "log_verbose"
flag_remove "low_battery"
flag_remove "in_menu"

# import multipass.cfg
${SCRIPTS_DIR}/network/multipass.sh > /dev/null &

# Bring up network and services
if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 1 ]; then
	/mnt/SDCARD/spruce/scripts/networkservices.sh &
fi

${SCRIPTS_DIR}/network/wifi_watchdog.sh > /dev/null &

unstage_archives_$PLATFORM

# Check for first_boot flags and run Unpacker accordingly
if flag_check "first_boot_${PLATFORM}"; then
    ${SCRIPTS_DIR}/archiveUnpacker.sh --silent &
    log_message "Unpacker started silently in background due to first_boot flag"
else
    ${SCRIPTS_DIR}/archiveUnpacker.sh
fi

check_and_handle_firmware_app &
check_and_hide_update_app &

if [ "$PLATFORM" = "A30" ]; then
    alsactl nrestore &

    # Restore and monitor brightness
    if [ -f "$TMP_BACKLIGHT_PATH)" ]; then
        BRIGHTNESS="$(cat $TMP_BACKLIGHT_PATH)"
        # only set non zero brightness value
        if [ "$BRIGHTNESS" -ne 0 ]; then 
            echo "$BRIGHTNESS" > /sys/devices/virtual/disp/disp/attr/lcdbl
        fi
    else
        echo 72 > /sys/devices/virtual/disp/disp/attr/lcdbl # = backlight setting at 5
    fi

    # listen hotkeys for brightness adjustment, volume buttons and power button
    ${SCRIPTS_DIR}/buttons_watchdog.sh &

    # rename ttyS0 to ttyS2 so that PPSSPP cannot read the joystick raw data
    mv /dev/ttyS0 /dev/ttyS2

    # create virtual joypad from keyboard input, it should create /dev/input/event4 system file
    cd "/mnt/SDCARD/spruce/bin"
    ./joypad $EVENT_PATH_KEYBOARD &

    # read joystick raw data from serial input and apply calibration,
    # then send analog input to /dev/input/event4 when in ANALOG_MODE (this is default)
    # and send keyboard input to /dev/input/event3 when in KEYBOARD_MODE.
    # Please send kill signal USR1 to switch to ANALOG_MODE
    # and send kill signal USR2 to switch to KEYBOARD_MODE
    ${SCRIPTS_DIR}/autoReloadCalibration.sh &

elif [ $PLATFORM = "Brick" ] || [ $PLATFORM = "SmartPro" ]|| [ $PLATFORM = "SmartProS" ]; then

    export PATH="/usr/trimui/bin:$PATH"
    export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
    chmod a+x /usr/bin/notify

    init_gpio_Brick

    syslogd -S

    if [ "$(jq -r '.wifi // 0' "$SYSTEM_JSON")" -eq 0 ]; then
        ifconfig wlan0 down
        killall -15 wpa_supplicant
        killall -9 udhcpc    
    fi

    # start all the trimui things and sleep long enough for the input devices to get
    # registered correctly before creating the virtual joypad on /dev/input/event4
    mkdir /tmp/trimui_inputd
    /etc/bluetooth/bluetoothd start
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/keymon &
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/trimui_btmanager &
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/trimui_inputd &
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/trimui_scened &
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/hardwareservice &
    sleep 0.3 ### wait long enough to create the virtual joypad

    # create virtual joypad from keyboard input, it should create /dev/input/event4 system file
    # TODO: verify that we can call this via absolute path
    cd "/mnt/SDCARD/spruce/bin"
    ./joypad $EVENT_PATH_KEYBOARD &

elif [ "$PLATFORM" = "Flip" ]; then

    echo 3 > /proc/sys/kernel/printk
    chmod a+x /usr/bin/notify

    export LD_LIBRARY_PATH=/usr/miyoo/lib:/usr/lib:/lib

    init_gpio_Flip

    insmod /lib/modules/rtk_btusb.ko
    /usr/miyoo/bin/btmanager &
    /usr/miyoo/bin/hardwareservice &
    /usr/miyoo/bin/miyoo_inputd &

    #joypad
    echo -1 > /sys/class/miyooio_chr_dev/joy_type
    #keyboard
    #echo 0 > /sys/class/miyooio_chr_dev/joy_type

    # Unlike on other devices, our .tmp_update hook on the Flip enters us before the vendor firmware update.
    perform_fw_update_Flip

    # listen for hotkeys for brightness adjustment, volume button, power button and bluetooth setting change
    ${SCRIPTS_DIR}/buttons_watchdog.sh &
    ${SCRIPTS_DIR}/mixer_watchdog.sh &
    ${SCRIPTS_DIR}/bluetooth_watchdog.sh &

    killall runmiyoo.sh
fi

# check whether to run first boot procedure
if flag_check "first_boot_${PLATFORM}"; then
    "${SCRIPTS_DIR}/firstboot.sh"
fi

${SCRIPTS_DIR}/powerbutton_watchdog.sh &
${SCRIPTS_DIR}/homebutton_watchdog.sh &
${SCRIPTS_DIR}/lid_watchdog.sh &
${SCRIPTS_DIR}/applySetting/idlemon_mm.sh &
${SCRIPTS_DIR}/low_power_warning.sh &

# check whether to auto-resume into a game
if flag_check "save_active"; then
    log_message "save_active flag detected. Autoresuming game."

    # Ensure device is properly initialized (volume, wifi, etc) before launching auto-resume
    /mnt/SDCARD/App/PyUI/launch.sh -startupInitOnly True

    # moving rather than copying prevents you from repeatedly reloading into a corrupted NDS save state;
    # copying is necessary for repeated save+shutdown/autoresume chaining though and is preferred when safe.
    MOVE_OR_COPY=cp
    if grep -q "Roms/NDS" "${FLAGS_DIR}/lastgame.lock"; then MOVE_OR_COPY=mv; fi

    # move command to cmd_to_run.sh so game switcher can work correctly
    $MOVE_OR_COPY "/mnt/SDCARD/spruce/flags/lastgame.lock" /tmp/cmd_to_run.sh && sync

    sleep 4
    nice -n -20 /tmp/cmd_to_run.sh &> /dev/null
    rm -f /tmp/cmd_to_run.sh # remove tmp command file after game exit; otherwise the game will load again in principal.sh later
    log_message "Auto Resume executed"
else
    log_message "Auto Resume skipped (no save_active flag)"
fi

${SCRIPTS_DIR}/autoIconRefresh.sh &
developer_mode_task &
update_checker &
# update_notification

# Initialize CPU settings


scaling_min_freq="$DEVICE_SMART_FREQ" ### default value, may be overridden in specific script
set_smart

# start main loop
log_message "Starting main loop"
${SCRIPTS_DIR}/principal.sh
