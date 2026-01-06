#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/rumble.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/amixer_volume_control.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/flip_a30_brightness.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/flip-system.json"
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
    [ -n "$6" ] && echo "$6" > "$LED_PATH/trigger"
    return 0
}


# used in principal.sh
enable_or_disable_rgb() {
    log_message "rgb led not supported on miyoo flip"
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
	RA_DIR="/mnt/SDCARD/RetroArch"
	if [ "$CORE" = "yabasanshiro" ]; then
		# "Error(s): /usr/miyoo/lib/libtmenu.so: undefined symbol: GetKeyShm" if you try to use non-Miyoo RA for this core
		export RA_BIN="ra64.miyoo"
	elif [ "$use_igm" = "False" ] || [ "$CORE" = "parallel_n64" ]; then
		export RA_BIN="retroarch-flip"
	else
		export RA_BIN="ra64.miyoo"
	fi
			
    if [ "$CORE" = "uae4arm" ]; then
		export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
	elif [ "$CORE" = "easyrpg" ]; then
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
    set_powersave
}

set_powersave(){
    unlock_governor 2>/dev/null
    echo "conservative" > /sys/class/devfreq/dmc/governor
    echo "conservative" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo "408000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
    echo "1104000" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    echo "1" > /sys/devices/system/cpu/cpu0/online
    echo "1" > /sys/devices/system/cpu/cpu1/online
    echo "0" > /sys/devices/system/cpu/cpu2/online
    echo "0" > /sys/devices/system/cpu/cpu3/online
    log_message "Enabling convervative mode"
    lock_governor 2>/dev/null
}

post_pyui_exit(){
    log_message "Miyoo Flip doesn't need to do anything  when exitting pyui" -v
}

launch_startup_watchdogs(){
    launch_common_startup_watchdogs
    /mnt/SDCARD/spruce/scripts/lid_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/buttons_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/mixer_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/bluetooth_watchdog.sh &
    /mnt/SDCARD/spruce/scripts/enable_zram.sh &
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

	# PortMaster ports location
    mkdir -p /mnt/sdcard/Roms/PORTS/ports/ 
    mount --bind /mnt/sdcard/Roms/PORTS/ /mnt/sdcard/Roms/PORTS/ports/
	
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

get_spruce_ra_cfg_location() {
    echo "/mnt/SDCARD/RetroArch/platform/retroarch-Flip.cfg"
}

reset_playback_pack() {
    log_message "*** reset playback path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    system_json_volume=$(cat $SYSTEM_JSON | grep -o '"vol":\s*[0-9]*' | grep -o [0-9]*)
    current_vol_name="SYSTEM_VOLUME_$system_json_volume"
    
    eval vol_value=\$$current_vol_name
    
    amixer sset 'SPK' "$vol_value%" > /dev/null
    amixer cset name='Playback Path' 0 > /dev/null
    amixer cset name='Playback Path' "$current_path" > /dev/null
}


set_playback_path() {
    volume_lv=$(amixer cget name='SPK Volume' | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    log_message "*** audioFunctions.sh: Volume level: $volume_lv" -v

    jack_status=$(cat /sys/class/gpio/gpio150/value) # 0 connected, 1 disconnected
    log_message "*** audioFunctions.sh: Jack status: $jack_status" -v

    # 0 OFF, 2 SPK, 3 HP
    playback_path=$([ $jack_status -eq 1 ] && echo 2 || echo 3)
    [ "$volume_lv" = 0 ] && [ "$playback_path" = 2 ] && playback_path=0
    log_message "*** audioFunctions.sh: Playback path: $playback_path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)

    amixer cset name='Playback Path' "$playback_path" > /dev/null
    # if coming off mute, ensure that there's a change so that volume doesn't spike
    ( (( current_path == 0 )) || (( current_path != playback_path )) ) && [ ! "$playback_path" = 0 ] \
      && amixer sset 'SPK' 1% > /dev/null && amixer sset 'SPK' "$volume_lv%" > /dev/null
}


run_mixer_watchdog() {
    # TODO: will need to fix for brick and tsp
    JACK_PATH=/sys/class/gpio/gpio150/value

    while true; do
        /mnt/SDCARD/spruce/bin64/inotifywait -e modify "$SYSTEM_JSON" >/dev/null 2>&1 &
        PID_INOTIFY=$!

        /mnt/SDCARD/spruce/bin64/gpiowait $JACK_PATH &
        PID_GPIO=$!

        wait -n

        log_message "*** mixer watchdog: change detected" -v

        kill $PID_INOTIFY $PID_GPIO 2>/dev/null

        set_playback_path
    done
}


new_execution_loop() {
    log_message "new_execution_loop Uneeded on this device" -v
}


volume_down() {
    amixer_volume_down
}

volume_up() {
    amixer_volume_up
}

get_volume_level() {
    amixer_get_volume_level
}


# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}

device_prepare_for_ports_run() {
    /mnt/SDCARD/spruce/flip/bind-new-libmali.sh
}

device_cleanup_after_ports_run() {
    /mnt/SDCARD/spruce/flip/unbind-new-libmali.sh
}