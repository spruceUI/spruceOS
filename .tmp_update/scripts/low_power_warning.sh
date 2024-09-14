#!/bin/sh

# >access SECURITY
# access: PERMISSION DENIED.
# >access security grid
# access: PERMISSION DENIED.
# >access main security grid
# access: PERMISSION DENIED.

LED_PATH="/sys/devices/platform/sunxi-led/leds/led1"
FLAG_PATH="/mnt/SDCARD/.tmp_update/flags"
PERCENT=2
SLEEP=5

dot_duration=0.2
dash_duration=0.6
intra_char_gap=0.2
inter_char_gap=0.6
inter_word_gap=1.4

morse_code_sos() {
    for symbol in "$@"; do
        case $symbol in
            ".") echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
                 echo 100 > /sys/devices/virtual/timed_output/vibrator/enable
                 sleep $dot_duration
                 ;;
            "-") echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
                 echo 100 > /sys/devices/virtual/timed_output/vibrator/enable
                 sleep $dash_duration
                 ;;
        esac
        echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
        echo 0 > /sys/devices/virtual/timed_output/vibrator/enable
        sleep $intra_char_gap
    done
    sleep $inter_word_gap
}

while true; do
    CAPACITY=$(cat /sys/class/power_supply/battery/capacity)

    if [ "$CAPACITY" -le $PERCENT ]; then 
        while [ "$CAPACITY" -le $PERCENT ]; do
            morse_code_sos "." "." "." "-" "-" "-" "." "." "."
            CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
        done

    elif [ -f ${FLAG_PATH}/ledon.lock ]; then
        echo 1 > ${LED_PATH}/brightness

    elif [ -f ${FLAG_PATH}/tlon.lock ] && \
         [ -f ${FLAG_PATH}/in_menu.lock ]; then
        echo 1 > ${LED_PATH}/brightness

    else
        echo 0 > ${LED_PATH}/brightness
    fi

    sleep $SLEEP
done &
