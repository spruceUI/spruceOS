#!/bin/sh

# MagicX Zero 40. Everything lives in magicx_a133p.sh; this file only names the
# device's own config. The touchscreen node is resolved at device_init.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/magicx_a133p.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/magicx-zero40-system.json"
}

# The Zero 40's XR829 carries Bluetooth on ttyS1; the Zero 28 and XU20 have no
# Bluetooth chip and keep the default. The base ships bluez, bluealsa and the
# XR829 firmware: this is its /etc/bluetooth/bt_init.sh_xr829 (rfkill pulse,
# hciattach, procd's bluetoothd) without the hcidump_xr logger, plus bluealsa.
device_bluetooth_supported() {
    return 0
}

device_bluetooth_up() {
    if [ ! -d /sys/class/bluetooth/hci0 ]; then
        echo 0 > /sys/class/rfkill/rfkill0/state
        sleep 1
        echo 1 > /sys/class/rfkill/rfkill0/state
        sleep 1
        ( cd / && exec hciattach -n ttyS1 xradio ) </dev/null >/dev/null 2>&1 &
        _n=0
        while [ ! -d /sys/class/bluetooth/hci0 ] && [ "$_n" -lt 8 ]; do
            sleep 1
            _n=$((_n + 1))
        done
    fi
    if ! pidof bluetoothd >/dev/null 2>&1; then
        /etc/bluetooth/bluetoothd start >/dev/null 2>&1
        sleep 1
    fi
    pidof bluealsa >/dev/null 2>&1 || zero40_start_bluealsa
}

device_bluetooth_down() {
    zero40_stop_bluealsa
    /etc/bluetooth/bluetoothd stop >/dev/null 2>&1
    killall bluetoothd hciattach 2>/dev/null
    echo 0 > /sys/class/rfkill/rfkill0/state
}

# The base's bluez-alsa is 1.3.1. Without --a2dp-volume it copies the headset's
# own AVRCP volume into a software gain (-64..0 dB) while the headset applies
# that volume as well, so a headset at half volume plays about 32 dB down even
# at full level. With it the samples are left alone and the level set through
# bt_headset_volume becomes the headset's own.
zero40_start_bluealsa() {
    ( cd / && exec bluealsa -p a2dp-source --a2dp-volume ) </dev/null >/dev/null 2>&1 &
}

# 1.3.1 can also wedge: its control thread waits for a stream drain while it
# holds the device lock, and when the stream ends first it waits forever. It
# then answers neither BlueZ (every connect fails) nor amixer, and ignores
# SIGTERM because the stuck thread is its main loop.
zero40_stop_bluealsa() {
    killall bluealsa 2>/dev/null || return 0
    _n=0
    while pidof bluealsa >/dev/null 2>&1 && [ "$_n" -lt 2 ]; do
        sleep 1
        _n=$((_n + 1))
    done
    killall -9 bluealsa 2>/dev/null
    return 0
}

# A headset came up: if bluealsa no longer answers, restart it so the next
# connect works, instead of failing until Bluetooth is turned off and on.
device_bt_audio_connected() {
    if pidof bluealsa >/dev/null 2>&1; then
        timeout 3 amixer -D bluealsa scontrols >/dev/null 2>&1
        if [ $? -ge 124 ]; then
            log_message "Zero 40: bluealsa stopped answering; restarting it"
            zero40_stop_bluealsa
            zero40_start_bluealsa
            return 0
        fi
    fi
    bt_headset_volume "$(get_volume_level)"
}
