#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** powerbutton_watchdog.sh: helperFunctions imported." -v

BIN_PATH="/mnt/SDCARD/spruce/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
FLAG_PATH="/mnt/SDCARD/spruce/flags"

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

while true ; do

    # listen to event0 and handle key press events
    $BIN_PATH/getevent /dev/input/event0 -exclusive | while read line; do
        case $line in
            *"key 1 116 1"*) # MENU key down
                # not in previous sleep event
                if ! flag_check "pb.sleep" && ! flag_check "pb.longpress" ; then
                    # start long press handler
                    kill $PID
                    long_press_handler &
                    PID=$!
                fi
            ;;
            *"key 1 116 0"*) # MENU key up
                # if NOT long press
                if flag_check "pb.longpress" ; then
                    # kill long press handler and remove flag
                    kill $PID
                    PID=""
                    flag_remove "pb.longpress"

                    # add sleep flag
                    flag_add "pb.sleep"

                    # PAUSE pany process that may crash the system during wakeup
                    killall -q -19 enforceSmartCPU.sh

                    # PAUSE any other running emulator or MainUI
                    killall -q -19 ra32.miyoo || \
                    killall -q -19 retroarch || \
                    killall -q -19 PPSSPPSDL || \
                    killall -q -19 drastic || \
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
    echo -n mem > /sys/power/state

    # wait long enough to ensure device enter sleep mode
    # sleep 1

    # update display setting after wakeup
    ENHANCE_SETTINGS=$(cat /sys/devices/virtual/disp/disp/attr/enhance)
    echo "$ENHANCE_SETTINGS" > /sys/devices/virtual/disp/disp/attr/enhance

    # wait long enough to ensure wakeup task is finished
    # sleep 2

    # RESUME any running emulator or MainUI
    killall -q -18 ra32.miyoo || \
    killall -q -18 retroarch || \
    killall -q -18 PPSSPPSDL || \
    killall -q -18 drastic || \
    killall -q -18 MainUI

    # RESUME any process that may crash the system during wakeup
    killall -q -18 enforceSmartCPU.sh

    # delete sleep flag, now ready for sleep again
    flag_remove "pb.sleep"
done