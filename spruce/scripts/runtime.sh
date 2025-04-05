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
SDCARD_PATH="/mnt/SDCARD"
export HOME="${SDCARD_PATH}"
SCRIPTS_DIR="${SDCARD_PATH}/spruce/scripts"

case "$PLATFORM" in
    "A30" | "Brick" | "SmartPro" ) SPRUCE_ETC_DIR="/mnt/SDCARD/miyoo/etc" ;;
    "Flip") SPRUCE_ETC_DIR="/mnt/SDCARD/miyoo355/etc" ;;
esac

# Resetting log file location
log_file="/mnt/SDCARD/Saves/spruce/spruce.log"

cores_online &

if [ "$PLATFORM" = "A30" ]; then
    echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger
    echo L,L2,R,R2,X,A,B,Y > /sys/module/gpio_keys_polled/parameters/button_config
    SWAPFILE="/mnt/SDCARD/cachefile"
    BIN_DIR="${SDCARD_PATH}/spruce/bin"

    export SYSTEM_PATH="${SDCARD_PATH}/miyoo"
    export PATH="$SYSTEM_PATH/app:${PATH}"
    export LD_LIBRARY_PATH="$SYSTEM_PATH/lib:${LD_LIBRARY_PATH}"

    # Create directories and mount in parallel
    (
        mkdir -p /var/lib/alsa
        mkdir -p /tmp/SATURN
        mount -o bind "/mnt/SDCARD/miyoo/var/lib" /var/lib &
        mount -o bind /mnt/SDCARD/miyoo/app /usr/miyoo/app &
        mount -o bind /mnt/SDCARD/miyoo/lib /usr/miyoo/lib &
        mount -o bind /mnt/SDCARD/miyoo/res /usr/miyoo/res &
        mount -o bind /tmp/SATURN /mnt/SDCARD/Emu/SATURN &
        mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
        mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
        mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
        wait
    )

    lcd_init 1

    # Stop NTPD
    nice -n -18 sh -c '/etc/init.d/sysntpd stop && /etc/init.d/ntpd stop' > /dev/null 2>&1 &

elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
    export SYSTEM_PATH="${SDCARD_PATH}/trimui"
    export PATH="$SYSTEM_PATH/app:${PATH}"
    BIN_DIR="${SDCARD_PATH}/spruce/bin64"

    # Create directories and mount in parallel
    (
        # Use Emu folder for Miyoo and TrimUI devices despite different name schemes
        mkdir -p "/mnt/SDCARD/Emus"
        mount --bind "/mnt/SDCARD/Emu" "/mnt/SDCARD/Emus" &
        # Use App folder for Miyoo and TrimUI devices despite different name schemes
        mkdir -p "/mnt/SDCARD/Apps"
        mount --bind "/mnt/SDCARD/App" "/mnt/SDCARD/Apps" &
        # Mask Roms/PORTS with Brick version
        mkdir -p "/mnt/SDCARD/Roms/PORTS-Brick"
        mount --bind "/mnt/SDCARD/Roms/PORTS-Brick" "/mnt/SDCARD/Roms/PORTS" &
        # Use appropriate RA config
        [ -f "/mnt/SDCARD/spruce/settings/platform/retroarch-$PLATFORM.cfg" ] && mount --bind "/mnt/SDCARD/spruce/settings/platform/retroarch-$PLATFORM.cfg" "/mnt/SDCARD/RetroArch/retroarch.cfg" &
        # mount Brick themes to hide A30 ones
        mkdir -p "/mnt/SDCARD/trimui/brickThemes"
        mount --bind "/mnt/SDCARD/trimui/brickThemes" "/mnt/SDCARD/Themes" &
        wait

        mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
        mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
        mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &

    )

fi

# Flag cleanup
flag_remove "themeChanged"
flag_remove "log_verbose"
flag_remove "low_battery"
flag_remove "in_menu"
flag_remove "emufresh"

log_message " " -v
log_message "---------Starting up---------"
log_message " " -v

# import multipass.cfg and start watchdog for new network additions via MainUI
nice -n 15 ${SCRIPTS_DIR}/wpa_watchdog.sh > /dev/null &

# Sanitize system JSON if needed
if ! jq '.' "$SYSTEM_JSON" > /dev/null 2>&1; then
    log_message "Runtime: Invalid System JSON detected, sanitizing..."
    jq '.' "$SYSTEM_JSON" > /tmp/system.json.clean 2>/dev/null || cp /mnt/SDCARD/spruce/settings/system.json /tmp/system.json.clean
    mv /tmp/system.json.clean "$SYSTEM_JSON"
fi

if [ "$PLATFORM" = "A30" ]; then
    # Check if WiFi is enabled
    wifi=$(grep '"wifi"' "$SYSTEM_JSON" | awk -F ':' '{print $2}' | tr -d ' ,')
    if [ "$wifi" -eq 0 ]; then
        touch /tmp/wifioff && killall -9 wpa_supplicant && killall -9 udhcpc && rfkill
        log_message "WiFi turned off"
    else
        touch /tmp/wifion
        log_message "WiFi turned on"
    fi

    killall -9 main ### SUPER important in preventing .tmp_update suicide
fi

# Bring up network and services
${SCRIPTS_DIR}/wifi_watchdog.sh > /dev/null &

unstage_archives_$PLATFORM

# Check for first_boot flags and run Unpacker accordingly
if flag_check "first_boot_${PLATFORM}"; then
    ${SCRIPTS_DIR}/archiveUnpacker.sh --silent &
    log_message "Unpacker started silently in background due to first_boot flag"
else
    ${SCRIPTS_DIR}/archiveUnpacker.sh
fi

{
    ${SCRIPTS_DIR}/romdirpostrofix.sh
    ${SCRIPTS_DIR}/emufresh_md5_multi.sh
} &

if [ "$PLATFORM" = "A30" ]; then
    alsactl nrestore &

    # Restore and monitor brightness
    if [ -f "/mnt/SDCARD/spruce/settings/sys_brightness_level" ]; then
        BRIGHTNESS=$(cat /mnt/SDCARD/spruce/settings/sys_brightness_level)
        # only set non zero brightness value
        if [ $BRIGHTNESS -ne 0 ]; then 
            echo ${BRIGHTNESS} > /sys/devices/virtual/disp/disp/attr/lcdbl
        fi
    fi

    # listen hotkeys for brightness adjustment, volume buttons and power button
    ${SCRIPTS_DIR}/buttons_watchdog.sh &
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
    ${SCRIPTS_DIR}/homebutton_watchdog.sh &

    # start watchdog for konami code
    ${SCRIPTS_DIR}/simple_mode_watchdog.sh &

    # don't hide or unhide apps in simple_mode
    if ! flag_check "simple_mode"; then
        check_and_handle_firmware_app &
        check_and_hide_update_app &
    fi

    check_and_move_p8_bins # don't background because we want the display call to block so the user knows it worked (right?)

    ${SCRIPTS_DIR}/low_power_warning.sh &

    # Load idle monitors before game resume or MainUI
    ${SCRIPTS_DIR}/applySetting/idlemon_mm.sh &

    # check whether to auto-resume into a game
    if flag_check "save_active"; then
        ${SCRIPTS_DIR}/autoRA.sh  &> /dev/null
        log_message "Auto Resume executed"
    else
        log_message "Auto Resume skipped (no save_active flag)"
    fi

    ${SCRIPTS_DIR}/autoIconRefresh.sh &

    swapon -p 40 "${SWAPFILE}"

    # Run scripts for initial setup
    #${SCRIPTS_DIR}/forcedisplay.sh
    ${SCRIPTS_DIR}/ffplay_is_now_media.sh &
    ${SCRIPTS_DIR}/checkfaves.sh &
    ${SCRIPTS_DIR}/credits_watchdog.sh &

elif [ $PLATFORM = "Brick" ] || [ $PLATFORM = "SmartPro" ]; then

    export PATH="/usr/trimui/bin:$PATH"
    export LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
    chmod a+x /usr/bin/notify
    INPUTD_SETTING_DIR_NAME=/tmp/trimui_inputd

    #PD11 pull high for VCC-5v
    echo 107 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio107/direction
    echo -n 1 > /sys/class/gpio/gpio107/value

    #rumble motor PH3
    echo 227 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio227/direction
    echo -n 0 > /sys/class/gpio/gpio227/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    echo -n in > /sys/class/gpio/gpio243/direction

    mkdir $INPUTD_SETTING_DIR_NAME

    echo 1 > /sys/class/led_anim/effect_enable 
    echo "FFFFFF" > /sys/class/led_anim/effect_rgb_hex_lr
    echo 1 > /sys/class/led_anim/effect_cycles_lr
    echo 1000 > /sys/class/led_anim/effect_duration_lr
    echo 1 >  /sys/class/led_anim/effect_lr

    [ -d "/mnt/SDCARD/trimui/res/lang" ] && mount --bind /mnt/SDCARD/trimui/res/lang /usr/trimui/res/lang

    syslogd -S

    /etc/bluetooth/bluetoothd start

    usbmode=$(/usr/trimui/bin/systemval usbmode)

    if [ "$usbmode" == "dock" ] ; then
        /usr/trimui/bin/usb_dock.sh
    elif [ "$usbmode" == "host" ] ; then
        /usr/trimui/bin/usb_host.sh
    else
        /usr/trimui/bin/usb_device.sh
    fi

    wifion=$(/usr/trimui/bin/systemval wifi)
    if [ "$wifion" != "1" ] ; then
        ifconfig wlan0 down
        killall -15 wpa_supplicant
        killall -9 udhcpc    
    fi


    ${SCRIPTS_DIR}/homebutton_watchdog.sh &

    # start all the trimui things and sleep long enough for the input devices to get
    # registered correctly before creating the virtual joypad on /dev/input/event4
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/keymon &
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/trimui_inputd &
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/trimui_scened &
    LD_LIBRARY_PATH=/usr/trimui/lib /usr/trimui/bin/hardwareservice &
    sleep 0.3 ### wait long enough to create the virtual joypad


    # create virtual joypad from keyboard input, it should create /dev/input/event4 system file
    # TODO: verify that we can call this via absolute path
    cd ${BIN_DIR}
    ./joypad /dev/input/event3 &

elif [ "$PLATFORM" = "Flip" ]; then

    echo 3 > /proc/sys/kernel/printk
    chmod a+x /usr/bin/notify

    if [ -d "/media/sdcard1/miyoo355/" ]; then
        export CUSTOMER_DIR=/media/sdcard1/miyoo355/
    else
        export CUSTOMER_DIR=/media/sdcard0/miyoo355/
    fi

    export LD_LIBRARY_PATH=/usr/miyoo/lib

    (
        mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
        mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
        mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    )

    #motor
    echo 20 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio20/direction
    echo -n 0 > /sys/class/gpio/gpio20/value
    # sleep 0.05
    # echo -n 1 > /sys/class/gpio/gpio20/value
    # sleep 0.05
    # echo -n 0 > /sys/class/gpio/gpio20/value

    #joypad
    echo -1 > /sys/class/miyooio_chr_dev/joy_type
    #keyboard
    #echo 0 > /sys/class/miyooio_chr_dev/joy_type

    sleep 0.1
    hdmipugin=$(cat /sys/class/drm/card0-HDMI-A-1/status)
    if [ "$hdmipugin" == "connected" ] ; then
        /usr/bin/fbdisplay /usr/miyoo/bin/skin_1080p/app_loading_bg.png &
    else
        /usr/bin/fbdisplay /usr/miyoo/bin/skin/app_loading_bg.png &
    fi

    mkdir -p /tmp/miyoo_inputd

    if [ "$(/usr/miyoo/bin/jsonval turboA)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_a
    else
        unlink /tmp/miyoo_inputd/turbo_a
    fi

    if [ "$(/usr/miyoo/bin/jsonval turboB)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_b
    else
        unlink /tmp/miyoo_inputd/turbo_b
    fi

    if [ "$(/usr/miyoo/bin/jsonval turboX)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_x
    else
        unlink /tmp/miyoo_inputd/turbo_x
    fi

    if [ "$(/usr/miyoo/bin/jsonval turboY)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_y
    else
        unlink /tmp/miyoo_inputd/turbo_y
    fi

    if [ "$(/usr/miyoo/bin/jsonval turboL)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_l
    else
        unlink /tmp/miyoo_inputd/turbo_l
    fi
    
    if [ "$(/usr/miyoo/bin/jsonval turboR)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_r
    else
        unlink /tmp/miyoo_inputd/turbo_r
    fi

    if [ "$(/usr/miyoo/bin/jsonval turboL2)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_l2
    else
        unlink /tmp/miyoo_inputd/turbo_l2
    fi
    
    if [ "$(/usr/miyoo/bin/jsonval turboR2)" = "1" ] ; then
        touch /tmp/miyoo_inputd/turbo_r2
    else
        unlink /tmp/miyoo_inputd/turbo_r2
    fi

    miyoo_fw_update=0
    miyoo_fw_dir=/media/sdcard0
    if [ -f /media/sdcard0/miyoo355_fw.img ] ; then
        miyoo_fw_update=1
        miyoo_fw_dir=/media/sdcard0
    elif [ -f /media/sdcard1/miyoo355_fw.img ] ; then
        miyoo_fw_update=1
        miyoo_fw_dir=/media/sdcard1
    fi

    if [ ${miyoo_fw_update} -eq 1 ] ; then
        export LD_LIBRARY_PATH=${CUSTOMER_DIR}/lib 
        cd $miyoo_fw_dir
        /usr/miyoo/apps/fw_update/miyoo_fw_update
    fi

    # mask stock USB file transfer app
    mount --bind /mnt/SDCARD/spruce/spruce /usr/miyoo/apps/usb_mass_storage/config.json

    # Use appropriate RA config
    [ -f "/mnt/SDCARD/spruce/settings/platform/retroarch-Flip.cfg" ] && mount --bind "/mnt/SDCARD/spruce/settings/platform/retroarch-Flip.cfg" "/mnt/SDCARD/RetroArch/retroarch.cfg" && \
        mount --bind "/mnt/SDCARD/spruce/settings/platform/retroarch-Flip.cfg" "/mnt/SDCARD/RetroArch/ra64.miyoo.cfg"

    # use appropriate loading images
    [ -d "/mnt/SDCARD/miyoo355/app/skin" ] && mount --bind /mnt/SDCARD/miyoo355/app/skin /usr/miyoo/bin/skin
    [ -d "/mnt/SDCARD/miyoo355/app/lang" ] && mount --bind /mnt/SDCARD/miyoo355/app/lang /usr/miyoo/bin/lang
    
	# PortMaster ports location
    mkdir -p /mnt/sdcard/MIYOO_EX/ports/ 
    mkdir -p /mnt/sdcard/.local/share/
    mount --bind /mnt/SDCARD/ROMS/PORTS/ /mnt/sdcard/MIYOO_EX/ports/ 
    mount --bind /mnt/sdcard/MIYOO_EX/PortMaster /root 
    mount --bind /mnt/sdcard/MIYOO_EX/PortMaster /mnt/sdcard/.local/share/

    ${SCRIPTS_DIR}/autoIconRefresh.sh &

    killall runmiyoo.sh

fi

developer_mode_task &
update_checker &
if [ "$PLATFORM" = "A30" ]; then
    update_notification
fi

# check whether to run first boot procedure
if flag_check "first_boot_${PLATFORM}"; then
    "${SCRIPTS_DIR}/firstboot.sh"
else
    log_message "First boot procedures skipped"
fi

# Initialize CPU settings
scaling_min_freq=1008000 ### default value, may be overridden in specific script
set_smart

# start main loop
log_message "Starting main loop"
${SCRIPTS_DIR}/principal.sh
