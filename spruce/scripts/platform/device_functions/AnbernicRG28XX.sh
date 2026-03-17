#!/bin/bash

. /mnt/SDCARD/spruce/scripts/platform/device_functions/AnbernicXXCommon.sh

device_init() {
	insmod /mnt/SDCARD/spruce/rg28xx/8188eu.ko > /mnt/SDCARD/Saves/spruce/rg28xx_8188eu_log.txt

    runtime_mounts_anbernic_34xxsp

    {
        sleep 10
        /mnt/SDCARD/anbernic_adbd/run_adbd.sh &
    } &
    /mnt/SDCARD/spruce/rg34xxsp/bin/joypad_shim &
}
