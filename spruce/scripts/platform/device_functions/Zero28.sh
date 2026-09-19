#!/bin/sh

# MagicX Mini Zero 28. Everything lives in magicx_a133p.sh; this file only
# names the device's own config.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/magicx_a133p.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/magicx-zero28-system.json"
}
