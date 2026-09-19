#!/bin/sh

# MagicX / XU RETRO XU20 V32. Everything lives in magicx_a133p.sh; this file only
# names the device's own config. The Hynitron touch node is resolved at device_init.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/magicx_a133p.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/magicx-xu20-system.json"
}
