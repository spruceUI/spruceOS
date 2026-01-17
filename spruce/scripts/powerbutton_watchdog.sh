#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/audioFunctions.sh

log_message "powerbutton_watchdog.sh: Started up."

RTC_WAKE_FILE="/sys/class/rtc/rtc0/wakealarm"
EMULATORS="ra32.miyoo ra64.miyoo ra64.trimui_${PLATFORM} retroarch retroarch.A30 retroarch.Flip retroarch.trimui drastic drastic32 drastic64 PPSSPPSDL_${PLATFORM} PPSSPPSDL_TrimUI MainUI flycast yabasanshiro yabasanshiro.trimui mupen64plus"
TMP_BACKLIGHT_PATH=/mnt/SDCARD/Saves/spruce/tmp_backlight
TMP_VOLUME_PATH=/mnt/SDCARD/Saves/spruce/tmp_volume

applicable_process_is_running() {
    pgrep -f "MainUI" >/dev/null || \
    pgrep -f "retroarch" >/dev/null || \
    pgrep -f "ra32.miyoo" >/dev/null || \
    pgrep -f "ra64.miyoo" >/dev/null || \
    pgrep -f "ra64.trimui" >/dev/null || \
    pgrep -f "drastic" >/dev/null || \
    pgrep -f "PPSSPPSDL" >/dev/null || \
    pgrep -f "flycast" >/dev/null || \
    pgrep -f "yabasanshiro" >/dev/null || \
    pgrep -f "mupen64plus" >/dev/null
}

get_wake_alarm() {
    sleep_setting=$(get_config_value '.menuOptions."Battery Settings".shutdownFromSleep.selected' "5m")
    # Map to corresponding seconds
    case "$sleep_setting" in
        Instant) echo "-1" ;;
        Off)     echo 0 ;;
        2m)      echo 120 ;;
        5m)      echo 300 ;;
        10m)     echo 600 ;;
        30m)     echo 1800 ;;
        60m)     echo 3600 ;;
        *)       echo 300 ;; # Default to 5m if no match
    esac
}

long_press_handler() {
    flag_add "pb.longpress"
    sleep 2
    flag_remove "pb.longpress"
    vibrate &
    /mnt/SDCARD/spruce/scripts/save_poweroff.sh
}


##### MAIN EXECUTION #####

# Initialize flags and tmpfiles
flag_remove "pb.longpress"
flag_remove "pb.sleep"
touch "$TMP_BACKLIGHT_PATH"
touch "$TMP_VOLUME_PATH"

while true; do

    # create a temporary FIFO so we can run getevent in background and read in this shell
    FIFO="/tmp/power_event_fifo.$$"
    rm -f "$FIFO"
    mkfifo "$FIFO" || {
        log_message "Failed to create FIFO $FIFO" -v
        sleep 1
        continue
    }

    # start getevent writing to the fifo in background, and capture its PID
    getevent -exclusive "$EVENT_PATH_POWER" > "$FIFO" 2>/dev/null &
    GETEVENT_PID=$!

    while IFS= read -r line < "$FIFO"; do
        case $line in

        # Power key down
        *"key $B_POWER 1"*)
            if ! flag_check "pb.sleep" && ! flag_check "pb.longpress"; then
                # start long press handler (kill existing handler safely if present)
                if [ -n "$PID" ]; then
                    kill "$PID" 2>/dev/null || true
                    wait "$PID" 2>/dev/null || true
                    PID=""
                fi
                long_press_handler &
                PID=$!
            fi
            ;;

        # Power key up
        *"key $B_POWER 0"*)
            # if NOT long press
            if flag_check "pb.longpress"; then
                # kill long press handler and remove flag
                if [ -n "$PID" ]; then
                    kill "$PID" 2>/dev/null || true
                    wait "$PID" 2>/dev/null || true
                    PID=""
                fi
                flag_remove "pb.longpress"

                # add sleep flag
                flag_add "pb.sleep"

                # Check settings to determine how long to set RTC wake timer

                WAKE_ALARM_SEC="$(get_wake_alarm)"

                # shutdown from sleep is neither Instant nor Off
                if [ "$WAKE_ALARM_SEC" -gt 0 ]; then
                    if applicable_process_is_running; then
                        echo "+$WAKE_ALARM_SEC" >"$RTC_WAKE_FILE"
                        cat "$DEVICE_BRIGHTNESS_PATH" > "$TMP_BACKLIGHT_PATH"
                        CURRENT_VOLUME="$(get_current_volume)"
                        echo $CURRENT_VOLUME > "$TMP_VOLUME_PATH"
                        echo 0 > $DEVICE_BRIGHTNESS_PATH
                        set_volume 0
                        flag_add "wake.alarm"
                    fi
                fi

                # shutdown from sleep is Instant
                if [ "$WAKE_ALARM_SEC" -eq -1 ]; then
                    if applicable_process_is_running; then
                        flag_add "sleep.powerdown"
                        cat "$DEVICE_BRIGHTNESS_PATH" > "$TMP_BACKLIGHT_PATH"
                        CURRENT_VOLUME="$(get_current_volume)"
                        echo $CURRENT_VOLUME > "$TMP_VOLUME_PATH"
                        echo 0 > $DEVICE_BRIGHTNESS_PATH
                        set_volume 0
                        vibrate &
                        killall getevent 2>/dev/null
                        sleep 0.1
                        /mnt/SDCARD/spruce/scripts/save_poweroff.sh
                    fi
                fi

                # PAUSE any process that may crash the system during wakeup
                killall -q -19 enforceSmartCPU.sh

                # PAUSE any other running emulator or MainUI (use exact matches)
                for EMU in $EMULATORS; do
                    pids=$(pgrep -x "$EMU" 2>/dev/null)
                    if [ -n "$pids" ]; then
                        kill -19 $pids 2>/dev/null || true
                        break
                    fi
                done

                # kill getevent program, prepare to break inner while loop
                if [ -n "$GETEVENT_PID" ]; then
                    kill "$GETEVENT_PID" 2>/dev/null || true
                    wait "$GETEVENT_PID" 2>/dev/null || true
                    GETEVENT_PID=""
                fi

                # small pause to let things settle
                sleep 0.5

                # now break inner while loop
                break
            fi
            ;;
        esac
    done

    # cleanup FIFO
    rm -f "$FIFO"

    sync
    enter_sleep

    if flag_check "wake.alarm"; then

        # If RTC alarm is cleared, we woke from from the alarm
        CURRENT_ALARM=$(cat "$RTC_WAKE_FILE" 2>/dev/null)

        if ! [ -z "$CURRENT_ALARM" ]; then
            # restore display and volume setting after wakeup
            cat "$TMP_BACKLIGHT_PATH" > $DEVICE_BRIGHTNESS_PATH
            ENHANCE_SETTINGS=$(cat /sys/devices/virtual/disp/disp/attr/enhance)
            echo "$ENHANCE_SETTINGS" >/sys/devices/virtual/disp/disp/attr/enhance

            # restore volume only when we actually woke from the alarm
            set_volume "$(cat "$TMP_VOLUME_PATH")"
            device_specific_wake_from_sleep
        fi
    fi

    # RESUME any running emulator or MainUI (use exact matches)
    for EMU in $EMULATORS; do
        pids=$(pgrep -x "$EMU" 2>/dev/null)
        if [ -n "$pids" ]; then
            kill -18 $pids 2>/dev/null || true
            break
        fi
    done

    # RESUME any process that may crash the system during wakeup
    killall -q -18 enforceSmartCPU.sh

    # delete sleep flag, now ready for sleep again
    flag_remove "pb.sleep"

    # Power down if awoken via alarm
    if flag_check "wake.alarm"; then

        # If RTC alarm is cleared, we woke from from the alarm
        CURRENT_ALARM=$(cat "$RTC_WAKE_FILE" 2>/dev/null)

        if [ -z "$CURRENT_ALARM" ]; then
            flag_remove "wake.alarm"
            flag_add "sleep.powerdown"

            if applicable_process_is_running; then
                vibrate &
                /mnt/SDCARD/spruce/scripts/save_poweroff.sh
            fi

        else
            echo 0 >"$RTC_WAKE_FILE"
            flag_remove "wake.alarm"
        fi

    fi
done
