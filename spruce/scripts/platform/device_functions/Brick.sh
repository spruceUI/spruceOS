#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_a133p.sh"

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/trim-ui-brick-system.json"
}

init_gpio_a133p() {
    #PD11 pull high for VCC-5v
    echo 107 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio107/direction
    echo -n 1 > /sys/class/gpio/gpio107/value

    #rumble motor PH3
    echo 227 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio227/direction
    echo -n 0 > /sys/class/gpio/gpio227/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    echo -n in > /sys/class/gpio/gpio243/direction
}

device_init() {
    device_init_a133p
    run_trimui_osdd
}


set_volume() {
    new_vol="${1:-0}" # default to mute if no value supplied
    SAVE_TO_CONFIG="${2:-true}"   # Optional 2nd arg, defaults to true
    scaled=$(( new_vol * 255 / 20 ))
    amixer cset 'numid=17' "$scaled"
    if [ "$SAVE_TO_CONFIG" = true ]; then
        save_volume_to_config_file "$new_vol"
    fi
}