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
    if ! pidof bluealsa >/dev/null 2>&1; then
        ( cd / && exec bluealsa -p a2dp-source ) </dev/null >/dev/null 2>&1 &
    fi
}

device_bluetooth_down() {
    killall bluealsa 2>/dev/null
    /etc/bluetooth/bluetoothd stop >/dev/null 2>&1
    killall bluetoothd hciattach 2>/dev/null
    echo 0 > /sys/class/rfkill/rfkill0/state
}
