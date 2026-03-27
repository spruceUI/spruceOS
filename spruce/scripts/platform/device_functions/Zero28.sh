#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_a133p.sh"

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/magicx-zero28-system.json"
}

init_gpio_a133p() {
    :
}

device_init() {
    device_init_a133p

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash 2>/dev/null
        chmod +x /bin/bash 2>/dev/null
    fi
}