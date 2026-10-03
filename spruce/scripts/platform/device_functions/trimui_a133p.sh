#!/bin/sh

# TrimUI's A133P boards: Brick, Brick Pro and Smart Pro. The SoC-level functions
# come from a133p.sh; this file adds what needs TrimUI's userland - the daemons
# (trimui_inputd, trimui_scened, ...), the OSD, the RGB LEDs and the stock SDL2
# bind. Sourced by Brick.sh, BrickPro.sh and SmartPro.sh.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/a133p.sh"
. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh"

# The stock BusyBox 1.27.2 has no timeout applet, so bounded bluetoothctl calls never
# ran and audio never reached a headset; spruce's own BusyBox has one.
BTCTL_TIMEOUT="/mnt/SDCARD/spruce/bin64/busybox timeout 2"


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

# hardwareservice applies the volume keys to the control named in
# /tmp/bt_alsa_volume_dev; the stock keymon wrote it, and spruce does not run keymon.
device_on_bt_audio_route() {
    if [ -z "$1" ]; then
        rm -f /tmp/bt_alsa_volume_dev
        return 0
    fi
    control=$(bt_headset_volume_controls | head -n 1)
    [ -n "$control" ] || return 0
    printf '%s' "$control" > /tmp/bt_alsa_volume_dev
}

# PyUI's device (get-bt-audio-device.sh): the first headset bluealsa holds an A2DP
# transport for, else nothing; it also points the volume keys at it.
bt_audio_device() {
    pcm=""
    # PyUI asks right after killing bluetoothd or disconnecting the headset, and
    # bluealsa can still list the transport for a moment: check both directly.
    if pidof bluetoothd >/dev/null 2>&1; then
        pcm=$($BTCTL_TIMEOUT bluealsa-aplay -L 2>/dev/null | grep '^bluealsa:.*PROFILE=a2dp' | head -n 1)
    fi
    mac=$(echo "$pcm" | sed -n 's/.*DEV=\([0-9A-Fa-f:]*\).*/\1/p')
    if [ -n "$mac" ] && ! $BTCTL_TIMEOUT bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
        pcm=""
        mac=""
    fi
    device_on_bt_audio_route "$mac"
    [ -z "$pcm" ] || echo "$pcm"
}

# The firmware attaches hci0 and runs bluetoothd, so the default bring-up is all
# it needs: it fills in what is missing and never restarts bluetoothd.
device_bluetooth_supported() {
    return 0
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
    # Bound from /tmp so the mount does not hold the card. See bluetooth-main.conf.
    { cp "${SPRUCE_ETC_DIR}/bluetooth-main.conf" /tmp/bluetooth-main.conf &&
        mount -o bind /tmp/bluetooth-main.conf /etc/bluetooth/main.conf; } &
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
                    # The stock stop runs "killall wpa_supplicant" and downs wlan0,
                    # taking ours with it. restart is a no-op while WiFi is off.
                    log_message "Restarting spruce's WiFi after the stock stop"
                    wifi_request restart
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
        # The firmware left the radio up; WiFi goes first (bluetooth.sh boot).
        hciconfig hci0 down
        # Restart, not start: the stock runtrimui.sh already started it with the
        # stock main.conf, before runtime_mounts_a133p bound ours over it.
        /etc/bluetooth/bluetoothd restart
        /mnt/SDCARD/spruce/scripts/bluetooth.sh boot
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
