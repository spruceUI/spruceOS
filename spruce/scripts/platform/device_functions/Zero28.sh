#!/bin/sh

# MagicX Mini Zero 28. Everything lives in magicx_a133p.sh; this file only
# names the device's own config.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/magicx_a133p.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/magicx-zero28-system.json"
}


# Zero28 has no rumble motor, so a call to vibrate should blink the LED instead, as a visual signal that the
# power or G button has been held long enough and can be released.
vibrate() {
    
    for _i in 0 1 2 ; do
        /mnt/SDCARD/spruce/scripts/platform/device_functions/utils/magicx/led.sh on
        sleep 0.05
        /mnt/SDCARD/spruce/scripts/platform/device_functions/utils/magicx/led.sh off
        sleep 0.05
    done
}

