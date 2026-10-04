#!/bin/sh

# MagicX Zero 40. Everything lives in magicx_a133p.sh; this file only names the
# device's own config. The touchscreen node is resolved at device_init.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/magicx_a133p.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/magicx-zero40-system.json"
}

# XR829 on ttyS1 (the Zero 28 and XU20 have no Bluetooth): the base's
# bt_init.sh_xr829 recipe without its hcidump_xr logger.
device_bluetooth_supported() {
    return 0
}

BT_HCI_WAIT=8
device_bluetooth_radio_up() {
    [ -d /sys/class/bluetooth/hci0 ] && return 0
    bt_rfkill_pulse /sys/class/rfkill/rfkill0/state
    bt_spawn hciattach -n ttyS1 xradio
}

device_bluetooth_radio_down() {
    killall hciattach 2>/dev/null
    echo 0 > /sys/class/rfkill/rfkill0/state
}

# The wrapper's own stop, which keeps the pairing keys on the card.
device_bluetoothd_stop() {
    /etc/bluetooth/bluetoothd stop >/dev/null 2>&1
    killall bluetoothd 2>/dev/null
}

# 1.3.1 can wedge (a drain waits forever under its lock) and then answers neither
# BlueZ nor amixer: a headset coming up restarts it. 4.x cannot wedge that way.
device_bt_audio_connected() {
    if pidof bluealsa >/dev/null 2>&1 && bluealsa --version 2>/dev/null | grep -q '^1\.'; then
        timeout 3 amixer -D bluealsa scontrols >/dev/null 2>&1
        if [ $? -ge 124 ]; then
            log_message "Zero 40: bluealsa stopped answering; restarting it"
            bt_stop_bluealsa
            bt_start_bluealsa
            return 0
        fi
    fi
    bt_headset_volume "$(get_volume_level)"
}
