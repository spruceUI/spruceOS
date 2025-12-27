#!/bin/sh


. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"

export_ld_library_path() {
    export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib"
}

get_sd_card_path() {
    echo "/mnt/SDCARD"
}

get_config_path() {
    echo "/mnt/SDCARD/Saves/trim-ui-smart-pro-s-system-system.json"
}

###############################################################################

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
    duration=50
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

    # Parse arguments in any order
    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    case "$intensity" in
            "Weak")   echo  50 > /sys/class/motor/max_scale ;;
            "Medium") echo  75 > /sys/class/motor/max_scale ;;
            "Strong") echo 100 > /sys/class/motor/max_scale ;;
    esac
    timer=0
    echo -n 65535 > /sys/class/motor/level
    while [ $timer -lt $duration ]; do
        sleep 0.002
        timer=$(($timer + 2))
    done &
    wait
    echo -n 0 > /sys/class/motor/level
}


rgb_led() {
    rgb_led_trimui "$@"
}


# used in principal.sh
enable_or_disable_rgb() {
    enable_file="/sys/class/led_anim/enable"
    disable_rgb="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
    if [ "$disable_rgb" = "True" ]; then
        chmod 777 "$enable_file" 2>/dev/null
        echo 0 > "$enable_file" 2>/dev/null
        chmod 000 "$enable_file" 2>/dev/null
    else
        chmod 777 "$enable_file" 2>/dev/null
        echo 1 > "$enable_file" 2>/dev/null
        # don't lock them back afterwards
    fi
}

enter_sleep() {
    log_message "Need to fix sleep on trimui smart pro s"
}

get_current_volume() {
    log_message "TODO: verify get_current_volume for SmartProS"
    amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%'
}

set_volume() {
    log_message "TODO: verify set_volume for SmartProS"
    new_vol="${1:-0}" # default to mute if no value supplied
    amixer set 'Soft Volume Master' "$new_vol"
}


reset_playback_pack() {
    log_message "TODO: verify reset_playback_pack for SmartProS"
    log_message "*** audioFunctions.sh: reset playback path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    system_json_volume=$(cat $SYSTEM_JSON | grep -o '"vol":\s*[0-9]*' | grep -o [0-9]*)
    current_vol_name="SYSTEM_VOLUME_$system_json_volume"
    
    eval vol_value=\$$current_vol_name
    
    amixer sset 'SPK' "$vol_value%" > /dev/null
    amixer cset name='Playback Path' 0 > /dev/null
    amixer cset name='Playback Path' "$current_path" > /dev/null
}

set_playback_path() {
    log_message "TODO: verify set_playback_path for SmartProS"
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
    log_message "run_mixer_watchdog unecessary for smart pro s?" -v
}

new_execution_loop() {
    log_message "new_execution_loop nothing todo" -v
}

get_spruce_ra_cfg_location() {
    echo "/mnt/SDCARD/RetroArch/platform/retroarch-SmartProS.cfg"
}

get_ra_cfg_location(){
	echo "/mnt/SDCARD/RetroArch/retroarch.cfg"
}

setup_for_retroarch_and_get_bin_location(){
    setup_for_retroarch_and_get_bin_location_trimui
}



# Send L3 and R3 press event, this would toggle in-game and pause in RA
# or toggle in-game menu in PPSSPP
send_virtual_key_L3R3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        echo $B_R3 1 # R3 down
        sleep 0.1
        echo $B_R3 0 # R3 up
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_JOYPAD
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
    log_message "prepare_for_pyui_launch not needed for Trim UI Smart Pro S " -v
}

post_pyui_exit(){
    log_message "post_pyui_exit not needed for Trim UI Smart Pro S " -v
}

launch_startup_watchdogs(){
    launch_common_startup_watchdogs
}

perform_fw_check(){
    log_message "perform_fw_check not needed for Trim UI Smart Pro S " -v
}


compare_current_version_to_version() {
    target_version="$1"
    current_version="$(cat /etc/version 2>/dev/null)"

    [ -z "$target_version" ] && target_version="1.0.0"
    [ -z "$current_version" ] && current_version="1.0.0"

    # Split versions into components
    C_1=$(echo "$current_version" | cut -d. -f1)
    C_2=$(echo "$current_version" | cut -d. -f2)
    C_3=$(echo "$current_version" | cut -d. -f3)
    C_2=${C_2:-0}
    C_3=${C_3:-0}

    T_1=$(echo "$target_version" | cut -d. -f1)
    T_2=$(echo "$target_version" | cut -d. -f2)
    T_3=$(echo "$target_version" | cut -d. -f3)
    T_2=${T_2:-0}
    T_3=${T_3:-0}

    i=1
    while [ $i -le 3 ]; do
        eval C=\$C_$i
        eval T=\$T_$i

        if [ "$C" -gt "$T" ]; then
            echo "newer"
            return 0
        elif [ "$C" -lt "$T" ]; then
            echo "older"
            return 2
        fi
        i=$((i + 1))
    done

    echo "same"
    return 1
}


# Should the above be merged into here?
check_if_fw_needs_update() {
    check_if_fw_needs_update_trimui
}

take_screenshot() {
    screenshot_path="$1"

    screenshot.sh "$screenshot_path"
}

device_specific_wake_from_sleep() {
    log_message "TODO: device_specific_wake_from_sleep for Trim UI Smart Pro S " 
}


init_gpio_SmartProS() {
    #5V enable
    # echo 335 > /sys/class/gpio/export
    # echo -n out > /sys/class/gpio/gpio335/direction
    # echo -n 1 > /sys/class/gpio/gpio335/value

    #fan off
    echo 0 > /sys/class/thermal/cooling_device0/cur_state 

    #rumble motor PH12
    echo 236 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio236/direction
    echo -n 0 > /sys/class/gpio/gpio236/value

    #Left/Right Pad PK12/PK16 , run in trimui_inputd
    # echo 332 > /sys/class/gpio/export
    # echo -n out > /sys/class/gpio/gpio332/direction
    # echo -n 1 > /sys/class/gpio/gpio332/value

    # echo 336 > /sys/class/gpio/export
    # echo -n out > /sys/class/gpio/gpio336/direction
    # echo -n 1 > /sys/class/gpio/gpio336/value

    #DIP Switch PL11 , run in trimui_inputd
    # echo 363 > /sys/class/gpio/export
    # echo -n in > /sys/class/gpio/gpio363/direction

    # load wifi and low power bluetooth modules
    modprobe aic8800_fdrv.ko
    modprobe aic8800_btlpm.ko

    #splash rumble
    echo 32768 > /sys/class/motor/level 
    sleep 0.2
    echo 0 > /sys/class/motor/level 
}

runtime_mounts_SmartProS() {
    # Mask Roms/PORTS with non-A30 version
    mkdir -p "/mnt/SDCARD/Roms/PORTS64"
    mount --bind "/mnt/SDCARD/Roms/PORTS64" "/mnt/SDCARD/Roms/PORTS" &    
    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    /mnt/SDCARD/spruce/brick/sdl2/bind.sh &
    wait
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/flip/bin/MainUI
}

device_init() {
    runtime_mounts_SmartProS

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
    run_trimui_osdd
    echo -n HOME > /tmp/trimui_osd/hotkeyshow   # allows button on top of device to pull up OSD

    tinymix set 23 1
    tinymix set 18 23
    tinymix set 26 1
    tinymix set 27 1
    tinymix set 28 1
    tinymix set 29 1

    echo 1 > /sys/class/drm/card0-DSI-1/rotate
    echo 1 > /sys/class/drm/card0-DSI-1/force_rotate

   
}

set_event_arg() {
    log_message "set_event_arg not needed for Trim UI Smart Pro S?" -v
}

set_default_ra_hotkeys() {
        
    RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-SmartProS.cfg"

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
    log_message "reset_playback_pack Uneeded on this device" -v
}

set_playback_path() {
    log_message "set_playback_path Uneeded on this device" -v
}

run_mixer_watchdog() {
    log_message "run_mixer_watchdog Uneeded on this device" -v
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