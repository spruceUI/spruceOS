#!/bin/sh
# Powkiddy RGB20SX device functions: the RGB30's, plus what differs.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/RGB30.sh"

# Same board as the RGB30, so a card moved between them keeps its firstboot.
get_firstboot_key() {
    echo "RGB30"
}

device_bluetooth_supported() {
    return 0
}
