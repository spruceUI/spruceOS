#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LED_PATH="/sys/devices/platform/sunxi-led/leds/led1"
SLEEP=30

dot_duration=0.2
dash_duration=0.6
intra_char_gap=0.2
inter_word_gap=1.4

morse_code_sos() {
    local vibrate=$1
    shift
    for symbol in "$@"; do
        case $symbol in
            ".") echo 1 > ${LED_PATH}/brightness
                 [ "$vibrate" = "true" ] && vibrate 100
                 sleep $dot_duration
                 ;;
            "-") echo 1 > ${LED_PATH}/brightness
                 [ "$vibrate" = "true" ] && vibrate 100
                 sleep $dash_duration
                 ;;
        esac
        echo 0 > ${LED_PATH}/brightness
        if [ "$vibrate" = "true" ]; then
            echo 0 > /sys/devices/virtual/timed_output/vibrator/enable
        fi
        sleep $intra_char_gap
    done
    sleep $inter_word_gap
}

while true; do
    CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
    PERCENT="$(setting_get "low_power_warning_percent")"

    # force a safe shutdown at 1% regardless of settings
    if [ "$CAPACITY" -le 1 ]; then
        if ! setting_get "skip_shutdown_confirm"; then
            setting_update "skip_shutdown_confirm" on
            flag_add "forced_shutdown"
        fi
        display -d 2 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Battery level is below 1%. Shutting down to prevent progress loss."
        /mnt/SDCARD/spruce/scripts/save_poweroff.sh
        exit
    fi

    # disable script if turned off in spruce.cfg
    [ "$PERCENT" = "Off" ] && sleep $SLEEP && continue

    if [ "$CAPACITY" -le "$PERCENT" ]; then
        vibrate_count=0
        flag_added=false
        while [ "$CAPACITY" -le "$PERCENT" ]; do

            if [ "$vibrate_count" -lt 2 ]; then
                morse_code_sos "true" "." "." "." "-" "-" "-" "." "." "."
                vibrate_count=$((vibrate_count + 1))
            else
                if [ "$flag_added" = false ]; then
                    flag_add "low_battery"
                    flag_added=true
                fi
                morse_code_sos "false" "." "." "." "-" "-" "-" "." "." "."
            fi

            CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
            PERCENT="$(setting_get "low_power_warning_percent")"

            # force a safe shutdown at 1% regardless of settings
            if [ "$CAPACITY" -le 1 ]; then
                if ! setting_get "skip_shutdown_confirm"; then
                    setting_update "skip_shutdown_confirm" on
                    flag_add "forced_shutdown"
                fi
                display -d 2 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Battery level is below 1%. Shutting down to prevent progress loss."
                /mnt/SDCARD/spruce/scripts/save_poweroff.sh
                exit
            fi

            # disable script if turned off in spruce.cfg
            [ "$PERCENT" = "Off" ] && sleep $SLEEP && continue
        done

    elif flag_check "ledon"; then
        echo 1 > ${LED_PATH}/brightness
        flag_remove "low_battery"

    elif flag_check "tlon" && flag_check "in_menu"; then
        echo 1 > ${LED_PATH}/brightness
        flag_remove "low_battery"

    else
        echo 0 > ${LED_PATH}/brightness
        flag_remove "low_battery"
    fi

    sleep $SLEEP
done &
