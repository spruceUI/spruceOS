#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/legacy.sh"
. "/mnt/SDCARD/spruce/scripts/platform/common64bit.sh"

export_ld_library_path() {
    export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:/usr/miyoo/lib:/usr/lib:/lib"
}

export_spruce_etc_dir() {
    export SPRUCE_ETC_DIR="/mnt/SDCARD/miyoo355/etc"
}

get_sd_card_path() {
    echo "/mnt/sdcard"
}

get_config_path() {
    echo "/mnt/SDCARD/Saves/flip-system.json"
}


get_conservative_policy_dir() {
    echo "$CPU_0_DIR/conservative"
}

###############################################################################

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
    rumble_gpio "$@"
}


# ---------------------------------------------------------------------------
# rgb_led <zones> <effect> [color] [duration_ms] [cycles] [A30/Flip led trigger]
#
# Controls RGB LEDs on TrimUI Brick / Smart Pro.
#
# PARAMETERS:
#   <zones>        A string containing any combination of: l r m 1 2
#                  (order does not matter)
#                  Zones resolve to:
#                     l  → left LED
#                     r  → right LED
#                     m  → middle LED
#                     1  → front LED f1
#                     2  → front LED f2
#                  Example: "lrm12", "m1", "r2", "l"
#
#   <effect>       One of the following keywords or numeric equivalents:
#                     0 | off | disable      → off
#                     1 | linear | rise      → linear rise
#                     2 | breath*            → breathing pattern
#                     3 | sniff              → "sniff" animation
#                     4 | static | on        → solid color
#                     5 | blink*1            → blink pattern 1
#                     6 | blink*2            → blink pattern 2
#                     7 | blink*3            → blink pattern 3
#
#   [color]        Hex RGB color (default: "FFFFFF")
#
#   [duration_ms]  Animation duration in milliseconds (default: 1000)
#
#   [cycles]       Number of animation cycles (default: 1)
#
#   [led trigger]  none battery-charging-or-full battery-charging battery-full 
#                  battery-charging-blink-full-solid usb-online ac-online 
#                  timer heartbeat gpio default-on mmc1 mmc0
#
#
# EXAMPLES:
#   rgb_led lrm breathe FF8800 2000 3 heartbeat
#   rgb_led m2 blink1 00FFAA
#   rgb_led 12 static
#   rgb_led r off
# ---------------------------------------------------------------------------

rgb_led() {

    # early out if disabled
	disable="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
	[ "$disable" = "True" ] && return 0
    [ -n "$6" ] && echo "$6" > "$LED_PATH/trigger"

    return 0
}


# used in principal.sh
enable_or_disable_rgb() {
    log_message "rgb led not supported on miyoo flip"
}

restart_wifi() {
    # Requires PLATFORM and WPA_SUPPLICANT_FILE to be set
    log_message "Restarting Wi-Fi interface wlan0 on Flip"

    # Bring the interface down and kill any running services
    ifconfig wlan0 down
    killall wpa_supplicant 2>/dev/null
    killall udhcpc 2>/dev/null

    # Bring the interface back up and reconnect
    ifconfig wlan0 up
    wpa_supplicant -B -i wlan0 -c "$WPA_SUPPLICANT_FILE"
    udhcpc -i wlan0 &
}

enter_sleep() {
    echo deep >/sys/power/mem_sleep
    echo -n mem >/sys/power/state
}

get_current_volume() {
    amixer get 'SPK' | sed -n 's/.*Mono: *\([0-9]*\).*/\1/p' | tr -d '[]%'
}

set_volume() {
    new_vol="${1:-0}" # default to mute if no value supplied
    amixer cset name='SPK Volume' "$new_vol"
}

get_ra_cfg_location(){
    if [ "$use_igm" = "True" ]; then
		echo "/mnt/SDCARD/RetroArch/ra64.miyoo.cfg"
	else
		echo "/mnt/SDCARD/RetroArch/retroarch.cfg"
	fi
}

setup_for_retroarch_and_get_bin_location(){
	if [ "$CORE" = "yabasanshiro" ]; then
		# "Error(s): /usr/miyoo/lib/libtmenu.so: undefined symbol: GetKeyShm" if you try to use non-Miyoo RA for this core
		export RA_BIN="ra64.miyoo"
	elif [ "$use_igm" = "False" ] || [ "$CORE" = "parallel_n64" ]; then
		export RA_BIN="retroarch-flip"
	else
		export RA_BIN="ra64.miyoo"
	fi
			
	if [ "$CORE" = "easyrpg" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
	elif [ "$CORE" = "yabasanshiro" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
	fi
	export CORE_DIR="$RA_DIR/.retroarch/cores64"

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

    echo "$RA_BIN"
}


send_virtual_key_L3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        sleep 0.1
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_JOYPAD
}

prepare_for_pyui_launch(){
    log_message "Miyoo Flip doesn't need to do anything  when launching pyui" -v
}

post_pyui_exit(){
    log_message "Miyoo Flip doesn't need to do anything  when exitting pyui" -v
}

launch_startup_watchdogs(){
    launch_common_startup_watchdogs
    ${SCRIPTS_DIR}/lid_watchdog.sh &
}

perform_fw_check(){
    log_message "Miyoo Flip can't perform firmware check?" -v
}


# Should the above be merged into here?
check_if_fw_needs_update() {
    VERSION="$(cat /usr/miyoo/version)"
    [ "$VERSION" -ge "$TARGET_FW_VERSION" ] && echo "false" || echo "true"
}

take_screenshot() {
    close_ppsspp_menu
    /mnt/SDCARD/spruce/flip/screenshot.sh "$screenshot_path"
}


device_specific_wake_from_sleep() {
    reset_playback_pack
}


init_gpio_Flip() {
    # Initialize rumble motor
    echo 20 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio20/direction
    echo -n 0 > /sys/class/gpio/gpio20/value

    # Initialize headphone jack
    if [ ! -d /sys/class/gpio/gpio150 ]; then
        echo 150 > /sys/class/gpio/export
        sleep 0.1
    fi
    echo in > /sys/class/gpio/gpio150/direction
}

runtime_mounts_Flip() {

    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &

    if [ ! -d /mnt/sdcard/Saves/userdata-flip ]; then
        log_message "Saves/userdata-flip does not exist. Populating surrogate /userdata directory"
        mkdir /mnt/sdcard/Saves/userdata-flip
        cp -R /userdata/* /mnt/sdcard/Saves/userdata-flip
        mkdir -p /mnt/sdcard/Saves/userdata-flip/bin
        mkdir -p /mnt/sdcard/Saves/userdata-flip/bluetooth
        mkdir -p /mnt/sdcard/Saves/userdata-flip/cfg
        mkdir -p /mnt/sdcard/Saves/userdata-flip/localtime
        mkdir -p /mnt/sdcard/Saves/userdata-flip/timezone
        mkdir -p /mnt/sdcard/Saves/userdata-flip/lib
        mkdir -p /mnt/sdcard/Saves/userdata-flip/lib/bluetooth
    fi

	if [ ! -f /mnt/SDCARD/Saves/userdata-flip/system.json ]; then
		cp /mnt/SDCARD/spruce/flip/miyoo_system.json /mnt/SDCARD/Saves/userdata-flip/system.json
	fi

    log_message "Mounting surrogate /userdata and /userdata/bluetooth folders"
    mount --bind /mnt/sdcard/Saves/userdata-flip/ /userdata
    mkdir -p /run/bluetooth_fix
    mount --bind /run/bluetooth_fix /userdata/bluetooth
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/flip/bin/MainUI

    /mnt/sdcard/spruce/flip/recombine_large_files.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/setup_32bit_chroot.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/mount_muOS.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/setup_32bit_libs.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1
    /mnt/sdcard/spruce/flip/bind_glibc.sh >> /mnt/sdcard/Saves/spruce/spruce.log 2>&1

    # use appropriate loading images
    [ -d "/mnt/SDCARD/miyoo355/app/skin" ] && mount --bind /mnt/SDCARD/miyoo355/app/skin /usr/miyoo/bin/skin
    
    # Mask Roms/PORTS with non-A30 version
    mkdir -p "/mnt/SDCARD/Roms/PORTS64"
    mount --bind "/mnt/SDCARD/Roms/PORTS64" "/mnt/SDCARD/Roms/PORTS" &

	# PortMaster ports location
    mkdir -p /mnt/sdcard/Roms/PORTS64/ports/ 
    mount --bind /mnt/sdcard/Roms/PORTS64/ /mnt/sdcard/Roms/PORTS64/ports/
	
	# Treat /spruce/flip/ as the 'root' for any application that needs it.
	# (i.e. PortMaster looks here for config information which is device specific)
    mount --bind /mnt/sdcard/spruce/flip/ /root 

    # Bind the correct version of retroarch so it can be accessed by PM
    mount --bind /mnt/sdcard/RetroArch/retroarch-flip /mnt/sdcard/RetroArch/retroarch
}


perform_fw_update_Flip() {
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
        cd $miyoo_fw_dir
        /usr/miyoo/apps/fw_update/miyoo_fw_update
        rm "${miyoo_fw_dir}/miyoo355_fw.img"
    fi
}


device_init() {
    runtime_mounts_Flip

    SCRIPTS_DIR="/mnt/SDCARD/spruce/scripts"


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

    # Can this be moved into launch_startup_watchdogs?
    # listen for hotkeys for brightness adjustment, volume button, power button and bluetooth setting change
    ${SCRIPTS_DIR}/buttons_watchdog.sh &
    ${SCRIPTS_DIR}/mixer_watchdog.sh &
    ${SCRIPTS_DIR}/bluetooth_watchdog.sh &
    ${SCRIPTS_DIR}/enable_zram.sh &

     killall runmiyoo.sh   
}

set_event_arg() {
    EVENT_ARG="-e /dev/input/event5"
}

set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-Flip.cfg"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    # Update RetroArch config with default values
    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"4\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"9\"" \
        "input_menu_toggle = \"escape\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_save_state_btn = \"10\"" \
        "input_screenshot_btn = \"1\"" \
        "input_shader_toggle_btn = \"11\"" \
        "input_state_slot_decrease_btn = \"13\"" \
        "input_state_slot_increase_btn = \"14\"" \
        "input_toggle_slowmotion_axis = \"+4\"" \
        "input_toggle_fast_forward_axis = \"+5\""

}