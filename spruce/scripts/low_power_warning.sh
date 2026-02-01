#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SLEEP=30

dot_duration=0.2
dash_duration=0.6
intra_char_gap=0.2
inter_word_gap=1.4

LOG_DIR="/mnt/SDCARD/Saves/spruce"
LOG_FILE="${LOG_DIR}/battery_log.txt"
LOG_INTERVAL=120 # 2 minutes in seconds
LAST_LOG=0
MAX_LINES=1000

morse_code_sos() {
    local do_vibrate=$1
    shift
    for symbol in "$@"; do
        case $symbol in
        ".")
            echo 1 >${LED_PATH}/brightness
            [ "$do_vibrate" = "true" ] && vibrate 100 &
            sleep $dot_duration
            ;;
        "-")
            echo 1 >${LED_PATH}/brightness
            [ "$do_vibrate" = "true" ] && vibrate 100 &
            sleep $dash_duration
            ;;
        esac
        echo 0 >${LED_PATH}/brightness
        # No need to set vibrate to off as we passed duration to vibrate function
        sleep $intra_char_gap
    done
    sleep $inter_word_gap
}

log_battery() {
    # Create directory if it doesn't exist
    [ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR"

    # Get current timestamp
    CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

    # Check charging status
    CHARGING=$(device_get_charging_status)

    # Append new log entry with appropriate status
    if [ "$CHARGING" = "Charging" ]; then
        echo "${CURRENT_TIME} - Charging: ${CAPACITY}%" >>"$LOG_FILE"
    else
        echo "${CURRENT_TIME} - Battery: ${CAPACITY}%" >>"$LOG_FILE"
    fi

    # Keep only last 1000 lines
    if [ "$(wc -l <"$LOG_FILE")" -gt "$MAX_LINES" ]; then
        sed -i '1d' "$LOG_FILE"
    fi
}

hard_shutdown() {
    CAPACITY=$1
    if [ "$CAPACITY" -le 1 ]; then
        flag_add "forced_shutdown"
        /mnt/SDCARD/spruce/scripts/save_poweroff.sh
        exit
    fi
}

# Log boot entry
CAPACITY=$(cat $BATTERY/capacity)
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
[ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR"
echo "${CURRENT_TIME} - Boot: ${CAPACITY}%" >>"$LOG_FILE"
if [ "$(wc -l <"$LOG_FILE")" -gt "$MAX_LINES" ]; then
    sed -i '1d' "$LOG_FILE"
fi
LAST_LOG=$(date +%s)

while true; do
    CAPACITY=$(device_get_battery_percent)
    PERCENT="$(get_config_value '.menuOptions."Battery Settings".lowPowerWarningPercent.selected' "4")"
    LED_MODE="$(get_config_value '.menuOptions."Battery Settings".ledMode.selected' "Always off")"
    
    # Add battery logging
    CURRENT_TIME=$(date +%s)
    if [ $((CURRENT_TIME - LAST_LOG)) -gt $LOG_INTERVAL ]; then
        log_battery
        LAST_LOG=$(date +%s) # Keep this as Unix timestamp
    fi

    # Set default value if PERCENT is empty or non-numeric
    case $PERCENT in
    '' | *[!0-9]*) PERCENT=4 ;;
    esac

    # force a safe shutdown at 1% regardless of settings
    hard_shutdown $CAPACITY

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
                    if flag_check "in_menu"; then
                        display -t "Battery has $CAPACITY% left. Charge or shutdown your device." --okay
                    else
                        flag_add "low_battery"
                    fi
                    flag_added=true
                fi
                morse_code_sos "false" "." "." "." "-" "-" "-" "." "." "."
            fi

            CAPACITY=$(device_get_battery_percent)
            PERCENT="$(get_config_value '.menuOptions."Battery Settings".lowPowerWarningPercent.selected' "4")"

            hard_shutdown $CAPACITY

            # disable script if turned off in spruce.cfg
            [ "$PERCENT" = "Off" ] && sleep $SLEEP && continue
        done
    elif [ "$LED_PATH" != "not applicable" ]; then
        if [ "$LED_MODE" = "Always on" ]; then
            echo 1 >${LED_PATH}/brightness
            flag_remove "low_battery"

        elif [ "$LED_MODE" = "On in menu only" ] && flag_check "in_menu"; then
            echo 1 >${LED_PATH}/brightness
            flag_remove "low_battery"

        else # if [ "$LED_MODE" = "Always Off" ]; then
            echo 0 >${LED_PATH}/brightness
            flag_remove "low_battery"
        fi
    fi

    sleep $SLEEP
done
