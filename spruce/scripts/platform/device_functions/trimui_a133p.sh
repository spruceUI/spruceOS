#!/bin/sh

# TrimUI's A133P boards: Brick, Brick Pro and Smart Pro. The SoC-level functions
# come from a133p.sh; this file adds what needs TrimUI's userland - the daemons
# (trimui_inputd, trimui_scened, ...), the OSD, the RGB LEDs and the stock SDL2
# bind. Sourced by Brick.sh, BrickPro.sh and SmartPro.sh.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/a133p.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh"


###############################################################################

rgb_led() {
    rgb_led_trimui "$@"
}

# used in principal.sh
enable_or_disable_rgb() {
    enable_or_disable_rgb_trimui "$@"
}

set_volume() {
    new_vol="${1:-0}" # default to mute if no value supplied
    SAVE_TO_CONFIG="${2:-true}"   # Optional 2nd arg, defaults to true
    SHOW_OSD="${3:-true}"   # Optional 3rd arg, defaults to true
    mkdir -p /tmp/system 2>/dev/null
    echo "$new_vol" > /tmp/system/set_volume 2>/dev/null
    if [ "$SAVE_TO_CONFIG" = true ]; then
        current_volume=$(jq -r '.vol' "$SYSTEM_JSON")

        if [ "$current_volume" -ne "$new_vol" ]; then
            save_volume_to_config_file "$new_vol"
            sed "s/\"vol\":[[:space:]]*[0-9]\+/\"vol\": $new_vol/" /mnt/UDISK/system.json > /mnt/UDISK/system.json.tmp && mv /mnt/UDISK/system.json.tmp /mnt/UDISK/system.json
            if ! pgrep MainUI >/dev/null && [ "$SHOW_OSD" = true ]; then
                /usr/trimui/osd/show_volume_msg.sh "$new_vol" &
            fi
        fi
    fi

}

prepare_for_pyui_launch(){
    rm -f /tmp/trimui_inputd/input_no_dpad
    rm -f /tmp/trimui_inputd/input_dpad_to_joystick
}

# Should the above be merged into here?
check_if_fw_needs_update() {
    check_if_fw_needs_update_trimui
}

runtime_mounts_a133p() {

    mount -o bind "${SPRUCE_ETC_DIR}/profile" /etc/profile &
    mount -o bind "${SPRUCE_ETC_DIR}/group" /etc/group &
    mount -o bind "${SPRUCE_ETC_DIR}/passwd" /etc/passwd &
    /mnt/SDCARD/spruce/brick/sdl2/bind.sh &
    wait
    touch /mnt/SDCARD/spruce/flip/bin/MainUI
    mount --bind /mnt/SDCARD/spruce/flip/bin/python3.10 /mnt/SDCARD/spruce/flip/bin/MainUI
}

# Stock runs its own wpa_supplicant (procd S96), which procd spawns just after
# enable_wifi has looked for one - so both end up on wlan0, deauthenticating each
# other for ~80 s. Import its networks, stop the service, then watch for 30 s
# because at device_init time procd has not registered it yet. Runtime only: the
# service stays enabled. Double-forked - runtime.sh waits for device_init's children.
stop_stock_wpa_supplicant_a133p() {
    [ -x /etc/init.d/wpa_supplicant ] || return 0
    import_wpa_networks_from /etc/wifi/wpa_supplicant.conf
    /etc/init.d/wpa_supplicant stop >/dev/null 2>&1
    (
        (
            _i=0
            while [ "$_i" -lt 60 ]; do
                for _pid in $(pgrep -f "wpa_supplicant.*-c/etc/wifi/"); do
                    kill -9 "$_pid" 2>/dev/null
                    /etc/init.d/wpa_supplicant stop >/dev/null 2>&1
                    log_message "Stopped the stock wpa_supplicant ($_pid) so spruce's is the only one"
                    # Ours does not recover from having shared wlan0, so restart it.
                    if pgrep -f "wpa_supplicant.*-c $WPA_SUPPLICANT_FILE" >/dev/null; then
                        log_message "spruce's wpa_supplicant was already running; restarting WiFi so it starts clean"
                        wifi_request restart
                    fi
                done
                usleep 500000
                _i=$((_i + 1))
            done
        ) &
    ) </dev/null >/dev/null 2>&1
}

device_init_a133p() {
    # Stock is "8 7 1 7": a long burst on ttyS0 at 115200 holds CPU0 long enough for
    # an i2c transfer to time out, and the stock handler panics on the late IRQ.
    # dmesg and pstore still record every level.
    echo "3 4 1 7" > /proc/sys/kernel/printk
    stop_stock_wpa_supplicant_a133p
    runtime_mounts_a133p

    export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
    chmod a+x /usr/bin/notify

    init_gpio_a133p

    (
        syslogd -S
        hwclock -s -u
        /etc/bluetooth/bluetoothd start
    ) &
    amixer set 'Soft Volume Master' 255 # reset this to max so we're not double attenuating vol with two different mixer controls
    run_trimui_blobs "trimui_inputd trimui_scened trimui_btmanager hardwareservice musicserver"

    (
        # Set volume on startup by simulating button presses
        # Alternative is shared memory to keymon
        # Delay is to prevent startup audio pop
        sleep 3
        {
            echo 1 115 1 # Vol up pressed
            echo 1 115 0 # Vol up released
            echo 1 114 1 # Vol down pressed
            echo 1 114 0 # Vol down released
            echo 0 0 0   # tell sendevent to exit
        } | sendevent $EVENT_PATH_VOLUME
        sleep 1
        echo 0 > /sys/class/speaker/mute
    ) &
}
