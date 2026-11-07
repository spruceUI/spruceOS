#!/bin/sh

# MagicX Mini Zero 28. Everything lives in MagicXCommon.sh; this file only
# names the device's own config.

. "/mnt/SDCARD/spruce/scripts/platform/oakmoss/MagicXCommon.sh"

get_config_path() {
    echo "/mnt/SDCARD/Saves/magicx-zero28-system.json"
}


# Zero28 has no rumble motor, so a call to vibrate should blink the LED instead, as a visual signal that the
# power or G button has been held long enough and can be released.
vibrate() {
    
    for _i in 0 1 2 ; do
        /mnt/SDCARD/spruce/scripts/platform/utils/magicx/led.sh on
        sleep 0.08
        /mnt/SDCARD/spruce/scripts/platform/utils/magicx/led.sh off
        sleep 0.08
    done
}

