#!/bin/sh

LED_PATH="/sys/devices/platform/sunxi-led/leds/led1"
PERCENT=4
SLEEP=5

dot_duration=0.2
dash_duration=0.6
intra_char_gap=0.2
inter_char_gap=0.6
inter_word_gap=1.4

morse_code_sos() {
    local vibrate=$1
    shift
    for symbol in "$@"; do
        case $symbol in
            ".") echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
                 if [ "$vibrate" = "true" ]; then
                     echo 100 > /sys/devices/virtual/timed_output/vibrator/enable
                 fi
                 sleep $dot_duration
                 ;;
            "-") echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
                 if [ "$vibrate" = "true" ]; then
                     echo 100 > /sys/devices/virtual/timed_output/vibrator/enable
                 fi
                 sleep $dash_duration
                 ;;
        esac
        echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
        if [ "$vibrate" = "true" ]; then
            echo 0 > /sys/devices/virtual/timed_output/vibrator/enable
        fi
        sleep $intra_char_gap
    done
    sleep $inter_word_gap
}

while true; do
    CAPACITY=$(cat /sys/class/power_supply/battery/capacity)

    if [ "$CAPACITY" -le $PERCENT ]; then 
        vibrate_count=0
        while [ "$CAPACITY" -le $PERCENT ]; do
            if [ "$vibrate_count" -lt 3 ]; then
                morse_code_sos "true" "." "." "." "-" "-" "-" "." "." "."
                vibrate_count=$((vibrate_count + 1))
            else
                morse_code_sos "false" "." "." "." "-" "-" "-" "." "." "."
            fi
            CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
        done

    elif flag_check "ledon"; then
        echo 1 > ${LED_PATH}/brightness

    elif flag_check "tlon" && flag_check "in_menu"; then
        echo 1 > ${LED_PATH}/brightness

    else
        echo 0 > ${LED_PATH}/brightness
    fi

    sleep $SLEEP
done &
