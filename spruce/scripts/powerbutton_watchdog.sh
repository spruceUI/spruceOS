#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** powerbutton_watchdog.sh: helperFunctions imported." -v

BIN_PATH="/mnt/SDCARD/spruce/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
FLAG_PATH="/mnt/SDCARD/spruce/flags"
WAKE_ALARM_SEC=300 # Fallback time in seconds until the wake alarm triggers
RTC_WAKE_FILE="/sys/class/rtc/rtc0/wakealarm"
SLEEP_FILE="/mnt/SDCARD/spruce/settings/sleep_powerdown"

long_press_handler() {
    # setup flag for long pressed event
    flag_add "pb.longpress"
    sleep 2
    flag_remove "pb.longpress"

    # now here long press is detected
    # trigger auto save and then power down the device

    /mnt/SDCARD/spruce/scripts/save_poweroff.sh
}

# ensure no flag files before main loop started
flag_remove "pb.longpress"
flag_remove "pb.sleep"

while true; do

    # listen to event0 and handle key press events
    $BIN_PATH/getevent /dev/input/event0 -exclusive | while read line; do
        case $line in
        *"key 1 116 1"*) # MENU key down
            # not in previous sleep event
            if ! flag_check "pb.sleep" && ! flag_check "pb.longpress"; then
                # start long press handler
                kill $PID
                long_press_handler &
                PID=$!
            fi
            ;;
        *"key 1 116 0"*) # MENU key up
            # if NOT long press
            if flag_check "pb.longpress"; then
                # kill long press handler and remove flag
                kill $PID
                PID=""
                flag_remove "pb.longpress"

                # add sleep flag
                flag_add "pb.sleep"

                # Check settings to determine how long to set RTC wake timer

                sleep_setting=$(setting_get "sleep_powerdown")
                # Map to corresponding seconds
                case "$sleep_setting" in
                Instant) WAKE_ALARM_SEC=-1 ;;
                Off) WAKE_ALARM_SEC=0 ;;
                2m) WAKE_ALARM_SEC=120 ;;
                5m) WAKE_ALARM_SEC=300 ;;
                10m) WAKE_ALARM_SEC=600 ;;
                30m) WAKE_ALARM_SEC=1800 ;;
                60m) WAKE_ALARM_SEC=3600 ;;
                esac

                if [ "$WAKE_ALARM_SEC" -gt 0 ]; then
                    if pgrep "MainUI" >/dev/null || pgrep "ra32.miyoo" >/dev/null || pgrep "drastic" >/dev/null || pgrep "PPSSPP" >/dev/null; then
                        echo "+$WAKE_ALARM_SEC" >"$RTC_WAKE_FILE"
                        cat /sys/devices/virtual/disp/disp/attr/lcdbl >/mnt/SDCARD/spruce/settings/tmp_sys_brightness_level
                        CURRENT_VOLUME=$(amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%')
                        echo $CURRENT_VOLUME >/mnt/SDCARD/spruce/settings/tmp_sys_volume_level
                        echo 0 >/sys/devices/virtual/disp/disp/attr/lcdbl
                        amixer set 'Soft Volume Master' 0
                        flag_add "wake.alarm"
                    fi
                fi

                if [ "$WAKE_ALARM_SEC" -eq -1 ]; then
                    if pgrep "MainUI" >/dev/null || pgrep "ra32.miyoo" >/dev/null || pgrep "drastic" >/dev/null || pgrep "PPSSPP" >/dev/null; then
                        flag_add "sleep.powerdown"
                        cat /sys/devices/virtual/disp/disp/attr/lcdbl >/mnt/SDCARD/spruce/settings/tmp_sys_brightness_level
                        CURRENT_VOLUME=$(amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%')
                        echo $CURRENT_VOLUME >/mnt/SDCARD/spruce/settings/tmp_sys_volume_level
                        echo 0 >/sys/devices/virtual/disp/disp/attr/lcdbl
                        amixer set 'Soft Volume Master' 0
                        /mnt/SDCARD/spruce/scripts/save_poweroff.sh
                    fi
                fi

                # PAUSE pany process that may crash the system during wakeup
                killall -q -19 enforceSmartCPU.sh

                # PAUSE any other running emulator or MainUI
                killall -q -19 ra32.miyoo ||
                    killall -q -19 retroarch ||
                    killall -q -19 PPSSPPSDL ||
                    killall -q -19 drastic ||
                    killall -q -19 MainUI

                // kill getevent program, prepare to break inner while loop
                kill $(pgrep -f "getevent /dev/input/event0 -exclusive")
                sleep 0.5

                // now break inner while loop
                break
            fi
            ;;
        esac
    done

    # notify MainUI (if it is running) the system is going to sleep
    touch /tmp/ui_sleeped_notification

    # ensure all cache is written to SD card
    sync

    # suspend to memory
    echo -n mem >/sys/power/state

    # wait long enough to ensure device enter sleep mode
    # sleep 1

    if flag_check "wake.alarm"; then

        # If RTC alarm is cleared, we woke from from the alarm
        CURRENT_ALARM=$(cat "$RTC_WAKE_FILE" 2>/dev/null)

        if ! [ -z "$CURRENT_ALARM" ]; then
            # update display and volume setting after wakeup
            cat /mnt/SDCARD/spruce/settings/tmp_sys_brightness_level >/sys/devices/virtual/disp/disp/attr/lcdbl
            ENHANCE_SETTINGS=$(cat /sys/devices/virtual/disp/disp/attr/enhance)
            echo "$ENHANCE_SETTINGS" >/sys/devices/virtual/disp/disp/attr/enhance
            amixer set 'Soft Volume Master' $(cat /mnt/SDCARD/spruce/settings/tmp_sys_volume_level)
        fi

    fi

    # wait long enough to ensure wakeup task is finished
    # sleep 2

    # RESUME any running emulator or MainUI
    killall -q -18 ra32.miyoo ||
        killall -q -18 retroarch ||
        killall -q -18 PPSSPPSDL ||
        killall -q -18 drastic ||
        killall -q -18 MainUI

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

            if pgrep "MainUI" >/dev/null || pgrep "ra32.miyoo" >/dev/null || pgrep "drastic" >/dev/null || pgrep "PPSSPP" >/dev/null; then
                /mnt/SDCARD/spruce/scripts/save_poweroff.sh
            fi

        else
            echo 0 >"$RTC_WAKE_FILE"
            flag_remove "wake.alarm"
        fi

    fi
done
