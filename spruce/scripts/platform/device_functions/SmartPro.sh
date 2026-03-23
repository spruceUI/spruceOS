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

send_menu_button_to_retroarch() {
    if pgrep "ra64.universal" >/dev/null; then
        send_virtual_key_L3R3
    fi
}

# this is a modified version of rumble_gpio with higher duty ratios for medium and weak intensities.
vibrate() {
    duration=50
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

    # Parse arguments in any order
    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    case "$intensity" in
        Strong)
            timer=0
            echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
            while [ $timer -lt $duration ]; do
                sleep 0.002
                timer=$((timer + 2))
            done
            echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
            ;;
        Medium)
            timer=0
            (
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.007
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$((timer + 8))
                done
            ) &
            ;;
        Weak)
            timer=0
            (
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.005
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$((timer + 6))
                done
            ) &
            ;;
        *)
            echo "Invalid intensity: $intensity"
            return 1
            ;;
    esac
}