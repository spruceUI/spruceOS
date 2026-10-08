#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


##### CONSTANTS #####

SLEEP=10

DOT_DURATION=0.2
DASH_DURATION=0.6
INTRA_CHAR_GAP=0.2
INTER_WORD_GAP=1.4


##### FUNCTIONS #####

morse_code_sos() {

    _do_vibrate=$1
    shift

    for _symbol in "$@"; do
        case $_symbol in
            ".")
                work_led_on
                [ "$_do_vibrate" = "true" ] && vibrate 100 &
                sleep $DOT_DURATION
                ;;
            "-")
                work_led_on
                [ "$_do_vibrate" = "true" ] && vibrate 100 &
                sleep $DASH_DURATION
                ;;
        esac
        work_led_off
        sleep $INTRA_CHAR_GAP
    done
    sleep $INTER_WORD_GAP
}

force_shutdown_if_needed() {
    first_reading=$1
    if [ "$first_reading" -le 1 ] 2>/dev/null; then
        sleep 1
        second_reading=$(device_get_battery_percent)
        case "$second_reading" in
            ''|*[!0-9]*)
                log_message "battery_level_watchdog: unreadable battery confirm sample '$second_reading'; skipping forced shutdown"
                return 0
                ;;
        esac
        if [ "$second_reading" -gt 1 ]; then
            log_message "battery_level_watchdog: battery read $first_reading%% not confirmed (re-read $second_reading%%); skipping forced shutdown"
            return 0
        fi
        if ! device_low_battery_shutdown_ok; then
            log_message "battery_level_watchdog: device declined the forced shutdown at $first_reading%%"
            return 0
        fi
        flag_add "forced_shutdown" --tmp
        /mnt/SDCARD/spruce/scripts/save_poweroff.sh
        exit
    fi
}


##### WATCHDOG LOOP #####

while true; do
    current_battery_percent=$(device_get_battery_percent)
    percent_to_warn_at="$(get_config_value '.menuOptions."Battery Settings".lowPowerWarningPercent.selected' "4")"
    led_mode="$(get_config_value '.menuOptions."Battery Settings".ledMode.selected' "Always off")"
    
    # force a safe shutdown at 1% regardless of settings
    force_shutdown_if_needed "$current_battery_percent"

    [ "$percent_to_warn_at" = "Off" ] && sleep $SLEEP && continue

    # Set default value if percent_to_warn_at is empty or non-numeric
    case $percent_to_warn_at in
    '' | *[!0-9]*) percent_to_warn_at=4 ;;
    esac

    if [ "$current_battery_percent" -le "$percent_to_warn_at" ]; then
        vibrate_count=0
        flag_added=false
        while [ "$current_battery_percent" -le "$percent_to_warn_at" ]; do

            if [ "$vibrate_count" -lt 2 ]; then
                morse_code_sos "true" "." "." "." "-" "-" "-" "." "." "."
                vibrate_count=$((vibrate_count + 1))
            else
                if [ "$flag_added" = false ]; then
                    if flag_check "in_menu"; then
                        display -t "Battery has $current_battery_percent% left. Charge or shutdown your device." --okay &
                    else
                        flag_add "low_battery" --tmp
                    fi
                    flag_added=true
                fi
                morse_code_sos "false" "." "." "." "-" "-" "-" "." "." "."
            fi

            current_battery_percent=$(device_get_battery_percent)
            percent_to_warn_at="$(get_config_value '.menuOptions."Battery Settings".lowPowerWarningPercent.selected' "4")"

            force_shutdown_if_needed "$current_battery_percent"

            [ "$percent_to_warn_at" = "Off" ] && break
            case $percent_to_warn_at in
            '' | *[!0-9]*) percent_to_warn_at=4 ;;
            esac
        done
    else
        flag_remove "low_battery"
        if [ "$led_mode" = "Always on" ]; then
            work_led_on
        elif [ "$led_mode" = "On in menu only" ] && flag_check "in_menu"; then
            work_led_on
        else # if [ "$led_mode" = "Always Off" ]; then
            work_led_off
        fi
    fi

    sleep $SLEEP
done
