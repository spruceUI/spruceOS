#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/audioFunctions.sh

log_message "*** powerbutton_watchdog.sh: helperFunctions imported." -v

BIN_PATH="/mnt/SDCARD/spruce/bin64"
if [ "$PLATFORM" = "A30" ]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin"
fi
SET_OR_CSET="cset"
[ "$PLATFORM" = "A30" ] && SET_OR_CSET="set"
NAME_QUALIFIER="name="
[ "$PLATFORM" = "A30" ] && NAME_QUALIFIER=""
AMIXER_CONTROL="'SPK Volume'"
[ "$PLATFORM" = "A30" ] && AMIXER_CONTROL="'Soft Volume Master'"

SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
FLAG_PATH="/mnt/SDCARD/spruce/flags"
WAKE_ALARM_SEC=300 # Fallback time in seconds until the wake alarm triggers
RTC_WAKE_FILE="/sys/class/rtc/rtc0/wakealarm"
EMULATORS="ra32.miyoo ra64.miyoo ra64.trimui_Brick ra64.trimui_SmartPro retroarch retroarch-flip drastic32 drastic64 PPSSPPSDL PPSSPPSDL_Flip PPSSPPSDL_Brick PPSSPPSDL_SmartPro MainUI flycast yabasanshiro yabasanshiro.trimui mupen64plus"

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

POWER_EVENT="/dev/input/event0"
[ "$PLATFORM" = "Flip" ] && POWER_EVENT="/dev/input/event2"

while true; do

    # listen to power event device and handle key press events
    $BIN_PATH/getevent -exclusive $POWER_EVENT | while read line; do
        case $line in
        *"key $B_POWER 1"*) # Power key down
            # not in previous sleep event
            if ! flag_check "pb.sleep" && ! flag_check "pb.longpress"; then
                # start long press handler
                kill $PID
                long_press_handler &
                PID=$!
            fi
            ;;
        *"key $B_POWER 0"*) # Power key up
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
                *) WAKE_ALARM_SEC=300 ;; # Default to 5m if no match
                esac

                if [ "$WAKE_ALARM_SEC" -gt 0 ]; then
                    if pgrep "MainUI" >/dev/null || pgrep "ra32.miyoo" >/dev/null || pgrep "ra64.miyoo" >/dev/null || pgrep "drastic" >/dev/null || pgrep "PPSSPP" >/dev/null; then
                        echo "+$WAKE_ALARM_SEC" >"$RTC_WAKE_FILE"
                        cat $DEVICE_BRIGHTNESS_PATH >/mnt/SDCARD/spruce/settings/tmp_sys_brightness_level
                        [ "$PLATFORM" = "A30" ] && CURRENT_VOLUME=$(amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%')
                        [ "$PLATFORM" = "Flip" ] && CURRENT_VOLUME=$(amixer get 'SPK' | sed -n 's/.*Mono: *\([0-9]*\).*/\1/p' | tr -d '[]%')
                        echo $CURRENT_VOLUME >/mnt/SDCARD/spruce/settings/tmp_sys_volume_level
                        echo 0 > $DEVICE_BRIGHTNESS_PATH
                        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" 0
                        flag_add "wake.alarm"
                    fi
                fi

                if [ "$WAKE_ALARM_SEC" -eq -1 ]; then
                    if pgrep "MainUI" >/dev/null || pgrep "ra32.miyoo" >/dev/null || pgrep "ra64.miyoo" >/dev/null || pgrep "drastic" >/dev/null || pgrep "PPSSPP" >/dev/null; then
                        flag_add "sleep.powerdown"
                        cat $DEVICE_BRIGHTNESS_PATH >/mnt/SDCARD/spruce/settings/tmp_sys_brightness_level
                        [ "$PLATFORM" = "A30" ] && CURRENT_VOLUME=$(amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%')
                        [ "$PLATFORM" = "Flip" ] && CURRENT_VOLUME=$(amixer get 'SPK' | sed -n 's/.*Mono: *\([0-9]*\).*/\1/p' | tr -d '[]%')
                        echo $CURRENT_VOLUME >/mnt/SDCARD/spruce/settings/tmp_sys_volume_level
                        echo 0 > $DEVICE_BRIGHTNESS_PATH
                        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" 0
                        /mnt/SDCARD/spruce/scripts/save_poweroff.sh
                    fi
                fi

                # PAUSE pany process that may crash the system during wakeup
                killall -q -19 enforceSmartCPU.sh

                # PAUSE any other running emulator or MainUI
                for EMU in $EMULATORS; do
                    killall -q -19 $EMU && break
                done

                # kill getevent program, prepare to break inner while loop
                kill $(pgrep -f "getevent -exclusive $POWER_EVENT")
                sleep 0.5

                # now break inner while loop
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
    [ "$PLATFORM" = "Flip" ] && echo deep >/sys/power/mem_sleep
    echo -n mem >/sys/power/state

    # wait long enough to ensure device enter sleep mode
    # sleep 1

    if flag_check "wake.alarm"; then

        # If RTC alarm is cleared, we woke from from the alarm
        CURRENT_ALARM=$(cat "$RTC_WAKE_FILE" 2>/dev/null)

        if ! [ -z "$CURRENT_ALARM" ]; then
            # update display and volume setting after wakeup
            cat /mnt/SDCARD/spruce/settings/tmp_sys_brightness_level > $DEVICE_BRIGHTNESS_PATH
            ENHANCE_SETTINGS=$(cat /sys/devices/virtual/disp/disp/attr/enhance)
            echo "$ENHANCE_SETTINGS" >/sys/devices/virtual/disp/disp/attr/enhance
        fi

        # shouldn't this be in the if?
        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $(cat /mnt/SDCARD/spruce/settings/tmp_sys_volume_level)
        [ "$PLATFORM" = "Flip" ] && reset_playback_pack
    fi

    # wait long enough to ensure wakeup task is finished
    # sleep 2

    # RESUME any running emulator or MainUI
    for EMU in $EMULATORS; do
        killall -q -18 $EMU && break
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

            if pgrep "MainUI" >/dev/null || pgrep "ra32.miyoo" >/dev/null || pgrep "ra64.miyoo" >/dev/null || pgrep "drastic*" >/dev/null || pgrep "PPSSPP*" >/dev/null || pgrep "flycast" >/dev/null || pgrep "yaba*" >/dev/null || pgrep "mupen64plus" >/dev/null; then
                /mnt/SDCARD/spruce/scripts/save_poweroff.sh
            fi

        else
            echo 0 >"$RTC_WAKE_FILE"
            flag_remove "wake.alarm"
        fi

    fi
done
