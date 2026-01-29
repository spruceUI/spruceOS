#!/bin/sh

rumble_gpio() {
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
                    sleep 0.005
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$((timer + 6))
                done
            ) &
            ;;
        Weak)
            timer=0
            (
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.003
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$((timer + 4))
                done
            ) &
            ;;
        *)
            echo "Invalid intensity: $intensity"
            return 1
            ;;
    esac
}