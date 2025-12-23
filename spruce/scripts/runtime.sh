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

[ "$LED_PATH" != "not applicable" ] && echo mmc0 > "$LED_PATH"/trigger

export PATH="$SYSTEM_PATH/app:${PATH}"
export HOME="/mnt/SDCARD"
SCRIPTS_DIR="/mnt/SDCARD/spruce/scripts"
TMP_BACKLIGHT_PATH=/mnt/SDCARD/Saves/spruce/tmp_backlight
TMP_VOLUME_PATH=/mnt/SDCARD/Saves/spruce/tmp_volume

rotate_logs
log_file="/mnt/SDCARD/Saves/spruce/spruce.log" # Resetting log file location
log_message "---------Starting up---------"

run_sd_card_fix_if_triggered    # do this before anything else
cores_online
set_performance
runtime_mounts_$PLATFORM

# Check if WiFi is enabled and bring up network services if so
enable_or_disable_wifi &

# import multipass.cfg and start wifi_watchdog
${SCRIPTS_DIR}/network/multipass.sh > /dev/null &
# ${SCRIPTS_DIR}/network/wifi_watchdog.sh > /dev/null &

# Flag cleanup
flag_remove "log_verbose" &
flag_remove "low_battery" &
flag_remove "in_menu" &

unstage_archives_wanted

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
    handle_a30_quirks &

    # listen hotkeys for brightness adjustment, volume buttons and power button
    ${SCRIPTS_DIR}/buttons_watchdog.sh &

    # rename ttyS0 to ttyS2 so that PPSSPP cannot read the joystick raw data
    mv /dev/ttyS0 /dev/ttyS2

    # create virtual joypad from keyboard input, it should create /dev/input/event4 system file
    cd "/mnt/SDCARD/spruce/bin"
    ./joypad $EVENT_PATH_KEYBOARD &
    ${SCRIPTS_DIR}/autoReloadCalibration.sh &

elif [ $PLATFORM = "Brick" ] || [ $PLATFORM = "SmartPro" ]; then

    export PATH="/usr/trimui/bin:$PATH"
    export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
    chmod a+x /usr/bin/notify

    init_gpio_${PLATFORM}

    syslogd -S

    /etc/bluetooth/bluetoothd start

    run_trimui_blobs
    echo -n MENU+SELECT > /tmp/trimui_osd/hotkeyshow

elif [ "$PLATFORM" = "SmartProS" ]; then

    export PATH=/usr/trimui/bin:$PATH
    export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
    chmod a+x /usr/bin/notify

    init_gpio_SmartProS

    #syslogd -S

    if [ "$(jq -r '.bluetooth // 0' "$SYSTEM_JSON")" -eq 0 ] ; then
        /etc/bluetooth/bt_init.sh start
        hpid=`pgrep hciattach`
        if [ "$hpid" == "" ] ; then
            hciattach -n ttyAS1 aic &
        fi        
        /etc/bluetooth/bluetoothd start
    fi

    run_trimui_blobs
    echo -n HOME > /tmp/trimui_osd/hotkeyshow   # allows button on top of device to pull up OSD

    tinymix set 23 1
    tinymix set 18 23
    tinymix set 26 1
    tinymix set 27 1
    tinymix set 28 1
    tinymix set 29 1

    echo 1 > /sys/class/drm/card0-DSI-1/rotate
    echo 1 > /sys/class/drm/card0-DSI-1/force_rotate

elif [ "$PLATFORM" = "Flip" ]; then

    echo 3 > /proc/sys/kernel/printk
    chmod a+x /usr/bin/notify

    export LD_LIBRARY_PATH=/usr/miyoo/lib:/usr/lib:/lib

    init_gpio_Flip

    insmod /lib/modules/rtk_btusb.ko
    /usr/miyoo/bin/btmanager &
    /usr/miyoo/bin/hardwareservice &
    /usr/miyoo/bin/miyoo_inputd &
    sleep 0.2   # leave this here or else buttons_watchdog.sh fails to start

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
    ${SCRIPTS_DIR}/enable_zram.sh &

    killall runmiyoo.sh

fi

# check whether to run first boot procedure
if flag_check "first_boot_${PLATFORM}"; then
    "${SCRIPTS_DIR}/firstboot.sh"
fi

if [ "$PLATFORM" != "MiyooMini" ]; then
    ${SCRIPTS_DIR}/set_up_swap.sh &
    ${SCRIPTS_DIR}/powerbutton_watchdog.sh &
    ${SCRIPTS_DIR}/lid_watchdog.sh &
    ${SCRIPTS_DIR}/applySetting/idlemon_mm.sh &
    ${SCRIPTS_DIR}/low_power_warning.sh &
fi

${SCRIPTS_DIR}/homebutton_watchdog.sh &

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
set_smart

# start main loop
log_message "Starting main loop"
${SCRIPTS_DIR}/principal.sh
