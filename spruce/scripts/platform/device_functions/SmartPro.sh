#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_a133p.sh"

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/trim-ui-smart-pro-system.json"
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

    #Left/Right Pad PD14/PD18
    echo 110 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio110/direction
    echo -n 1 > /sys/class/gpio/gpio110/value

    echo 114 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio114/direction
    echo -n 1 > /sys/class/gpio/gpio114/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    echo -n in > /sys/class/gpio/gpio243/direction
}

get_fw_version() {
    tr -d ' \t\n' < /etc/version 2>/dev/null
}

device_init() {
    device_init_a133p

    version="$(get_fw_version)"
    if [ "$version" != "1.1.0" ]; then
        run_trimui_osdd
    fi

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash
        chmod +x /bin/bash
    fi
}

send_virtual_key_L3R3() {
    {
        echo $B_L3 1 # L3 down
        echo $B_R3 1 # R3 down
        sleep 0.1
        echo $B_L3 0 # R3 up
        echo $B_R3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP
}

send_menu_button_to_retroarch() {
    if pgrep "ra64.trimui_$PLATFORM" >/dev/null; then
        send_virtual_key_L3R3
    fi
}