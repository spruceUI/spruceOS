#!/bin/sh


. "/mnt/SDCARD/spruce/scripts/platform/device_functions/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/legacy_display.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/sleep_functions.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/trim-ui-smart-pro-s-system.json"
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
# The switch is "DIP Switch PL11" on this SoC - gpio363, not the a133p line's
# gpio243, which does not exist here. init_gpio_SmartProS leaves it commented out
# because trimui_inputd owns the pin, but that also means trimui_inputd has
# already exported it, so it can simply be read.
#
# Verified on hardware that the raw value is the same 1/0 trimui_scened hands
# scene.sh, by flipping the switch with the action set to "LED off": LEDs off
# reads 1, LEDs on reads 0.
device_get_switch_position() {
    cat /sys/class/gpio/gpio363/value 2>/dev/null
}

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

# Toggle the RGB LEDs between the configured colour and off, through spruce's own
# LED system (not the stock ledc.sh, whose shmvar-based brightness is dead here).
# "Off" is a static 000000 since effect=0 only freezes the animation on its last
# colour. Reads the left LED's current colour to decide which way to flip.
toggle_led() {
    cur="$(cat /sys/class/led_anim/effect_rgb_hex_l 2>/dev/null | tr -d ' ')"
    hex="$(led_color_hex)"
    if [ "$cur" = "000000" ]; then
        rgb_led lrm12 static "$hex" &
    else
        rgb_led lrm12 static "000000" &
    fi
}

set_volume() {
    new_vol="${1:-0}" # default to mute if no value supplied
    SAVE_TO_CONFIG="${2:-true}"   # Optional 2nd arg, defaults to true

    mkdir -p /tmp/system 2>/dev/null
    echo "$new_vol" > /tmp/system/set_volume 2>/dev/null

    if [ "$SAVE_TO_CONFIG" = true ]; then
        current_volume=$(jq -r '.vol' "$SYSTEM_JSON")

        if [ "$current_volume" -ne "$new_vol" ]; then
            save_volume_to_config_file "$new_vol"
            sed "s/\"vol\":[[:space:]]*[0-9]\+/\"vol\": $new_vol/" /mnt/UDISK/system.json > /mnt/UDISK/system.json.tmp && mv /mnt/UDISK/system.json.tmp /mnt/UDISK/system.json
            if ! pgrep MainUI >/dev/null; then
                /usr/trimui/osd/show_volume_msg.sh "$new_vol" &
            fi
        fi
    fi

}


get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON"
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

send_virtual_key_L3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        sleep 0.1
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP
}

prepare_for_pyui_launch(){
    log_message "prepare_for_pyui_launch not needed for Trim UI Smart Pro S " -v
}

post_pyui_exit(){
    log_message "post_pyui_exit not needed for Trim UI Smart Pro S " -v
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
    /mnt/SDCARD/spruce/bin64/kmsgrab "$screenshot_path"
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

    #splash rumble
    echo 32768 > /sys/class/motor/level 
    sleep 0.2
    echo 0 > /sys/class/motor/level 
}

runtime_mounts_SmartProS() {
	# PortMaster ports location
    mkdir -p /mnt/SDCARD/Roms/PORTS/ports/ 
    mount --bind /mnt/SDCARD/Roms/PORTS/ /mnt/SDCARD/Roms/PORTS/ports/

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

    # load wifi and low power bluetooth modules
    (
        hwclock -s -u
        modprobe aic8800_fdrv.ko
        modprobe aic8800_btlpm.ko

        if [ "$(jq -r '.bluetooth // 0' "$SYSTEM_JSON")" -eq 0 ]; then
            /etc/bluetooth/bt_init.sh start

            hpid="$(pgrep hciattach)"
            if [ -z "$hpid" ]; then
                hciattach -n ttyAS1 aic &
            fi

            /etc/bluetooth/bluetoothd start
        fi
    ) &


    device_run_tsps_blobs
    device_run_thermal_process

    # Install the configured switch action into /usr/trimui/scene so the physical
    # switch follows Settings -> Button Settings -> Switch action. --now also
    # adopts, once, whatever action was already installed - on the Brick line that
    # is whatever the old fn_editor app last wrote, and it outlives the SD card.
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-switch-action --now

    run_osd="$(get_config_value '.menuOptions."System Settings".trimuiOSD.selected' "False")"
    [ "$run_osd" = "True" ] && run_trimui_osdd

    echo 1 > /sys/class/speaker/mute

    tinymix set 23 1
    tinymix set 18 23
    tinymix set 26 1
    tinymix set 27 1
    tinymix set 28 1
    tinymix set 29 1
    amixer set DAC 255 # reset this to max so we're not double attenuating vol with two different mixer controls

    echo 1 > /sys/class/drm/card0-DSI-1/rotate
    echo 1 > /sys/class/drm/card0-DSI-1/force_rotate
    
    (
        # Set volume on startup by simulating button presses
        # Alternative is shared memory to keymon
        # Delay is to prevent audio pop
        sleep 3
        {
            echo 1 115 1 # Vol up pressed
            echo 1 115 0 # Vol up released
            echo 1 114 1 # Vol down pressed
            echo 1 114 0 # Vol down released
            echo 0 0 0   # tell sendevent to exit
        } | sendevent $EVENT_PATH_VOLUME 
        sleep 3
        echo 0 > /sys/class/speaker/mute
    ) &
}

set_event_arg_for_idlemon() {
    log_message "set_event_arg_for_idlemon not needed for Trim UI Smart Pro S?" -v
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

device_lid_open(){
    # device has no lid so it's always open
    return 1
}

device_prepare_for_ports_run() {
    log_message "device_prepare_for_ports_run uneeded on this device" -v
}

device_cleanup_after_ports_run() {
    device_delay_then_check_trimui_blobs
}

WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

device_exit_sleep(){
    restore_cores_online
    if [ -f /tmp/wifi_on ]; then
        # wait for wlan0 to appear (up to ~5s)
        for _ in 1 2 3 4 5; do
            ip link show wlan0 >/dev/null 2>&1 && break
            sleep 1
        done

        if ! pidof wpa_supplicant >/dev/null 2>&1; then
            enable_or_disable_wifi_per_system_json
        fi
    fi
    device_run_tsps_blobs
    device_run_thermal_process
    (
        # Core 0 won't offline immediately, wait a bit to get rid of it
        sleep 10
        restore_cores_online
    ) &
    clear_wake_alarm $WAKE_ALARM_PATH
}

trigger_device_sleep() {
    echo -n mem >/sys/power/state
}

device_enter_sleep() {    
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    disable_wifi

    save_cores_online
    cores_online 0
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    device_stop_thermal_process
    trigger_device_sleep
}

device_delay_then_check_trimui_blobs() {
    (
        # They seem to die ~5s after ports close
        sleep 5
        device_run_tsps_blobs
    ) &

}

device_run_tsps_blobs() {
    run_trimui_blobs "trimui_inputd trimui_scened trimui_btmanager hardwareservice musicserver"
}

device_prepare_for_poweroff() {
    touch /tmp/trimui_osd/osdd_quit
    disable_wifi
}

device_home_button_pressed() {
    # The Smart Pro S has no Fn keys, only the top Home button (KEY_HOMEPAGE) and
    # the switch. The stock OSD daemon (trimui_osdd) is absent on this device, so
    # the old "touch /tmp/show_osdd" was a no-op. Instead run the action the user
    # picked in Settings -> Button Settings -> Home button action, through the
    # shared perform_action dispatch (button_actions.sh, sourced by
    # buttons_watchdog.sh) that the Menu button also uses.
    action="$(get_config_value '.menuOptions."Button Settings".homeAction.selected' "Game Switcher")"
    perform_action "$action"

    # perform_action leaves game-state cleanup to the caller (as the hold-home
    # path in homebutton_watchdog.sh does). Clear it only for actions that
    # actually end the game; menu/LED/screenshot leave the game running.
    case "$action" in
        "Game Switcher"|"Exit game")
            rm -f /tmp/cmd_to_run.sh
            rm -f /mnt/SDCARD/spruce/flags/lastgame.lock
            ;;
    esac
}

device_stop_thermal_process(){
    killall thermal-watchdog 2>/dev/null
    pid=$(ps -eo pid,args | grep '[a]daptive_fan.py' | awk '{print $1}')
    [ -n "$pid" ] && kill "$pid"
    echo 0 > /sys/class/thermal/cooling_device0/cur_state
}

device_run_thermal_process(){
    /mnt/SDCARD/spruce/smartpros/bin/update-thermal-watchdog-to-setting
}

set_backlight() {
    val="$1"

    # Clamp input to 1–10
    [ "$val" -lt 1 ] && val=1
    [ "$val" -gt 10 ] && val=10

    # Convert 1–10 → 1–255
    val_255=$(( (val - 1) * 254 / 9 + 1 ))

    # actually change the backlight
    echo "$val_255" > /sys/class/backlight/backlight0/brightness

    # update device system json
    tmp="${SYSTEM_JSON}.tmp.$$"
    jq ".backlight = $val" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON" || rm -f "$tmp"
}


device_system_handles_sdcard_unmount() {
    # return 0 = true
    # return non-zero = false
    return 1 # SmartProS leaves dirty bit set?
}
