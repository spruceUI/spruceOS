#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** powerbutton_watchdog.sh: helperFunctions imported." -v

BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
FLAG_PATH="/mnt/SDCARD/spruce/flags"

kill_current_process() {
    pid=$(ps | grep cmd_to_run | grep -v grep | sed 's/[ ]\+/ /g' | cut -d' ' -f2)
    ppid=$pid
    while [ "" != "$pid" ]; do
        ppid=$pid
        pid=$(pgrep -P $ppid)
    done

    if [ "" != "$ppid" ]; then
        kill -9 $ppid
    fi
}

long_press_handler() {
    # setup flag for long pressed event
    flag_add "pb.longpress"
    sleep 2
    flag_remove "pb.longpress"

    # exit if MainUI is running
    if flag_check "in_menu" ; then
        return 0
    fi

    # kill app without reboot if not emulator is running 
    if cat /tmp/cmd_to_run.sh | grep -q -v '/mnt/SDCARD/Emu' ; then
        kill_current_process
        return 0
    fi

    # kill PICO8 without reboot if PICO8 is running
    if pgrep "pico8_dyn" > /dev/null; then
        killall -q -15 pico8_dyn
        return 0
    fi

    # now here long press is detected
    # trigger auto save and then power down the device

    # notify user with vibration and led 
    echo heartbeat > /sys/devices/platform/sunxi-led/leds/led1/trigger
    vibrate

    # kill principle and runtime first so no new app / MainUI will be loaded anymore
    killall -q -15 runtime.sh
    killall -q -15 principal.sh

    # kill enforceSmartCPU first so no CPU setting is changed during shutdown
    killall -q -15 enforceSmartCPU.sh

    # trigger auto save and send kill signal 
    if pgrep "ra32.miyoo" > /dev/null ; then
        # {
        #     echo 1 1 0   # MENU up
        #     echo 1 57 1  # A down
        #     echo 1 57 0  # A up
        #     echo 0 0 0   # tell sendevent to exit
        # } | $BIN_PATH/sendevent /dev/input/event3
        # sleep 0.3
        killall -q -15 ra32.miyoo
    elif pgrep "PPSSPPSDL" > /dev/null ; then
        {
            echo 1 314 1  # SELECT down
            echo 3 2 255  # L2 down
            echo 3 2 0    # L2 up
            echo 1 314 0  # SELECT up
            echo 0 0 0    # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event4
        sleep 1
        killall -q -15 PPSSPPSDL
    else
        killall -q -15 retroarch
        killall -q -15 drastic
        killall -q -9 MainUI
    fi

    # wait until emulator or MainUI exit 
    while killall -q -0 ra32.miyoo || \
          killall -q -0 retroarch || \
          killall -q -0 PPSSPPSDL || \
          killall -q -0 drastic || \
          killall -q -0 MainUI ; do 
        sleep 0.5
    done

    # show saving screen
    show_image "/mnt/SDCARD/.tmp_update/res/save.png"

    # Created save_active flag
    flag_add "save_active"

    # Saved current sound settings
    alsactl store

    # sync files and power off device
    sync
    poweroff
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
                    long_press_handler &
                    PID=$!
                fi
            ;;
            *"key 1 116 0"*) # MENU key up
                # if NOT long press
                if flag_check "pb.longpress" ; then
                    # kill long press handler and remove flag
                    kill $PID
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

    # ensure all cache is written to SD card 
    sync

    # suspend to memory
    echo -n mem > /sys/power/state

    # wait long enough to ensure device enter sleep mode
    sleep 1

    # update display setting after wakeup
    ENHANCE_SETTINGS=$(cat /sys/devices/virtual/disp/disp/attr/enhance)
    echo "$ENHANCE_SETTINGS" > /sys/devices/virtual/disp/disp/attr/enhance

    # wait long enough to ensure wakeup task is finished
    sleep 2

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