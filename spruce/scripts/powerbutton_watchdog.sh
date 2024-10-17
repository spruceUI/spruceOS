#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** powerbutton_watchdog.sh: helperFunctions imported." -v

BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
FLAG_PATH="/mnt/SDCARD/spruce/flags"

long_press_handler() {
    # setup flag for long pressed event
    flag_add "pb.longpress"
    sleep 2
    flag_remove "pb.longpress"

    # now here long press is detected
    # trigger auto save and then power down the device

    # notify user with vibration and led 
    echo heartbeat > /sys/devices/platform/sunxi-led/leds/led1/trigger
    vibrate

    # kill principle first so no new app / MainUI will be loaded anymore
    killall -q -15 principal.sh

    # kill enforceSmartCPU first so no CPU setting is changed during shutdown
    killall -q -15 enforceSmartCPU.sh                

    # trigger auto save and send kill signal 
    if pgrep "ra32.miyoo" > /dev/null ; then
        {
            echo 1 1 0   # MENU up
            echo 1 57 1  # A down
            echo 1 57 0  # A up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
        sleep 0.3
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

    # show saving screen
    show_image "/mnt/SDCARD/.tmp_update/res/save.png" 3

    # wait until emulator or MainUI exit 
    while killall -q -0 ra32.miyoo || \
          killall -q -0 retroarch || \
          killall -q -0 PPSSPPSDL || \
          killall -q -0 drastic || \
          killall -q -0 MainUI ; do 
        sleep 0.5
    done

    if flag_check "syncthing"; then
        log_message "Syncthing is enabled, WiFi connection needed"

        if check_and_connect_wifi; then
            /mnt/SDCARD/App/Syncthing/syncthing_sync_check.sh --shutdown
        fi
    fi

    flag_remove "syncthing_startup_synced"

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

# listen to event0 and handle key press events
$BIN_PATH/getevent /dev/input/event0 | while read line; do
    case $line in
        *"key 1 116 1"*) # MENU key down
            # not in previous sleep event 
            if ! flag_check "pb.sleep" ; then
                # start long press handler
                long_press_handler &
                PID=$!

            # delete sleep flag, now ready for sleep again
            else
                flag_remove "pb.sleep"            
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

                sleep 0.5

                # PAUSE any running emulator or MainUI
                killall -q -19 ra32.miyoo
                killall -q -19 retroarch
                killall -q -19 PPSSPPSDL
                killall -q -19 drastic
                killall -q -19 MainUI

                sleep 0.5

                # ensure all cache is written to SD card 
                sync
                
                # suspend to memory
                echo -n mem > /sys/power/state
            fi
        ;;
        *"key 1 143 0"*) # Wakeup 
            # wait long enough to handle any wakeup step, including restore wifi  
            sleep 3
            
            # RESUME any running emulator or MainUI
            killall -q -18 ra32.miyoo
            killall -q -18 retroarch
            killall -q -18 PPSSPPSDL
            killall -q -18 drastic
            killall -q -18 MainUI

            # wait long enough for emulator to resume 
            sleep 2

            # RESUME any process that may crash the system during wakeup
            killall -q -18 enforceSmartCPU.sh

            # delete sleep flag, now ready for sleep again
            flag_remove "pb.sleep"
        ;;
    esac
done 
