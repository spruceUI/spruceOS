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
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/flip_a30_brightness.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"

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


are_headphones_plugged_in() {
    gpio_path="/sys/class/gpio/gpio150/value"

    if [ ! -f "$gpio_path" ]; then
        return 1  # false (not plugged in)
    fi

    value=$(cat "$gpio_path" 2>/dev/null | tr -d '[:space:]')

    if [ "$value" = "0" ]; then
        return 0  # true (plugged in)
    else
        return 1  # false
    fi
}


get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON"
}

set_volume() {
    VOLUME_LV="$1"
    SAVE_TO_CONFIG="${2:-true}"   # Optional 2nd arg, defaults to true
    VOLUME_RAW=$(( VOLUME_LV * 5 ))    
    log_message "Setting volume to ${VOLUME_RAW}"


    if [ "$VOLUME_RAW" -eq 0 ]; then
        amixer sset "Playback Path" "OFF" >/dev/null 2>&1
    else
        #TODO can we prevent peaking audio if going from 0 to non-0?

        if are_headphones_plugged_in; then
            amixer sset "Playback Path" "HP" >/dev/null 2>&1
        else
            amixer sset "Playback Path" "SPK" >/dev/null 2>&1
        fi

        amixer cset "name='SPK Volume'" "$VOLUME_RAW" >/dev/null 2>&1
        
        # Volume of '5' doesn't always work so go to 10 then '5' and it seems to
        if [ "$VOLUME_RAW" -eq 5 ]; then
            amixer cset "name='SPK Volume'" 10 >/dev/null 2>&1
            amixer cset "name='SPK Volume'" 5 >/dev/null 2>&1
        fi
    fi

    # Call save_volume_to_config_file only if SAVE_TO_CONFIG is true
    if [ "$SAVE_TO_CONFIG" = true ]; then
        save_volume_to_config_file "$VOLUME_LV"
    fi
}

fix_sleep_sound_bug() {
    config_volume=$(get_volume_level)

    if [ "$config_volume" -ne 0 ]; then
        log_message "Restoring volume to ${config_volume}"
        amixer cset numid=2 0
        amixer cset numid=5 0
        if are_headphones_plugged_in; then
            amixer cset numid=2 3
        else
            amixer cset numid=2 2
        fi
        set_volume "$(( config_volume ))"
    fi
}

volume_down() {
    VOLUME_LV=$(get_volume_level)
    if [ $VOLUME_LV -gt 0 ] ; then
        VOLUME_LV=$((VOLUME_LV-1))
        set_volume "$(( VOLUME_LV ))"
    fi
}

volume_up() {
    VOLUME_LV=$(get_volume_level)
    if [ $VOLUME_LV -lt 20 ] ; then
        VOLUME_LV=$((VOLUME_LV+1))
        set_volume "$(( VOLUME_LV ))"
    fi
}


WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

trigger_device_sleep() {
    echo deep >/sys/power/mem_sleep
    echo -n mem >/sys/power/state
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"

    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    trigger_device_sleep
}

device_exit_sleep() {
    fix_sleep_sound_bug
    echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
}

device_lid_sensor_ready() {
    [ -e "/sys/devices/platform/hall-mh248/hallvalue" ]
}

device_lid_open(){
    head -c 1 "/sys/devices/platform/hall-mh248/hallvalue" 2>/dev/null
}

get_current_volume() {
    amixer get 'SPK' | sed -n 's/.*Mono: *\([0-9]*\).*/\1/p' | tr -d '[]%'
}

setup_for_retroarch_and_get_bin_location(){
	RA_DIR="/mnt/SDCARD/RetroArch"
	if [ "$CORE" = "yabasanshiro" ]; then
		# "Error(s): /usr/miyoo/lib/libtmenu.so: undefined symbol: GetKeyShm" if you try to use non-Miyoo RA for this core
		export RA_BIN="ra64.miyoo"
	elif [ "$use_igm" = "False" ] || [ "$CORE" = "parallel_n64" ]; then
		export RA_BIN="retroarch.Flip"
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
    } | sendevent $EVENT_PATH_READ_INPUTS_SPRUCE
}

prepare_for_pyui_launch(){
    set_performance
    echo "performance" > /sys/class/devfreq/dmc/governor
    (
        # SDL2 takes forever, let it initialize before going to powersave
        sleep 5
        set_smart
        unlock_governor 2>/dev/null
    ) &
}

launch_startup_watchdogs(){
    launch_common_startup_watchdogs_v2 "true"

    # Why do we need this on flip? What exactly does it do?
    # The name is kinda confusing. I think it monitors for headphones?
    /mnt/SDCARD/spruce/scripts/mixer_watchdog.sh &

    #BT is broken so don't bother with it
    #/mnt/SDCARD/spruce/scripts/bluetooth_watchdog.sh &
    
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


close_ppsspp_menu() {

    if pgrep -f "PPSSPPSDL" >/dev/null; then
        log_message "homebutton_watchdog.sh: Closing PPSSPP menu."
        # use sendevent to send SELECT + R1 combo buttons to PPSSPP
        {
            echo $B_RIGHT 1  
            echo $B_RIGHT 0  
            echo $B_A 1  
            echo $B_A 0  
        } > /tmp/ppsspp_events.txt


        # run sendevent in a fully detached subshell
        (
            sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP < /tmp/ppsspp_events.txt
        ) < /dev/null > /dev/null 2>&1 &

        sleep 0.5
    fi
}

take_screenshot() {
    close_ppsspp_menu
    /mnt/SDCARD/spruce/flip/screenshot.sh "$screenshot_path"
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
    mount --bind /mnt/sdcard/RetroArch/retroarch.Flip /mnt/sdcard/RetroArch/retroarch
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
    /mnt/SDCARD/spruce/flip/bind-new-libmali.sh

}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e /dev/input/event5"
}

set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"

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

reset_playback_pack() {
    VOLUME_LV=$(get_volume_level)
    set_volume "$(( VOLUME_LV ))"
}


run_mixer_watchdog() {
    JACK_PATH=/sys/class/gpio/gpio150/value

    while true; do

        /mnt/SDCARD/spruce/bin64/gpiowait $JACK_PATH &
        PID_GPIO=$!
        wait -n

        log_message "*** mixer watchdog: change detected" -v

        kill $PID_GPIO 2>/dev/null
        VOLUME_LV=$(get_volume_level)
        set_volume "$(( VOLUME_LV ))"
    done
}


new_execution_loop() {
    log_message "new_execution_loop Uneeded on this device" -v
}

# 'Discharging', 'Charging', or 'Full' are possible values. Mind the capitalization.
device_get_charging_status() {
	cat "$BATTERY/status"
}

device_get_battery_percent() {
	cat "$BATTERY/capacity"
}

device_prepare_for_ports_run() {
    log_message "device_prepare_for_ports_run uneeded" -v
}

device_cleanup_after_ports_run() {
    log_message "device_cleanup_after_ports_run uneeded" -v
}


device_wifi_power_on() { 
    echo 1 > /sys/class/rkwifi/wifi_power
    sleep 1
}

device_wifi_power_off() { 
    echo 0 > /sys/class/rkwifi/wifi_power
}