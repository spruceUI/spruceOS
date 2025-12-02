#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

runifnecessary() {
    a=$(pgrep "$1")
    if [ "$a" = "" ] ; then
        $2 &
    fi
}

# Check for -buttonListenerMode in arguments
redirect_output=1
for arg in "$@"; do
    if [ "$arg" = "-buttonListenerMode" ]; then
        redirect_output=0
        break
    fi
done

# Launch (and subsequently close) MainUI with various quirks depending on PLATFORM
case "$PLATFORM" in
    "A30" )
        # make soft link to serial port with original device name, so MainUI can use it to calibrate joystick
        ln -s /dev/ttyS2 /dev/ttyS0

        # send signal USR2 to joystickinput to switch to KEYBOARD MODE
        # this allows joystick to be used as DPAD in MainUI
        killall -q -USR2 joystickinput

        # send signal USR1 to joystickinput to switch to ANALOG MODE
        killall -q -USR1 joystickinput
        touch /tmp/fbdisplay_exit
        cat /dev/zero > /dev/fb0
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/a30/sdl2"
        export LD_LIBRARY_PATH="/usr/miyoo/lib"


        cmd="/mnt/SDCARD/spruce/bin/python/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device MIYOO_A30 \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        if [ $redirect_output -eq 1 ]; then
            sh -c "$cmd \"\$@\" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1" sh "$@"
        else
            # Run normally
            sh -c "$cmd \"\$@\"" sh "$@"
        fi

        # remove soft link
        rm /dev/ttyS0
    ;;

    "Brick" | "SmartPro" )
        tinymix set 9 1
        tinymix set 1 0

        export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH
        cd /usr/trimui/bin

        runifnecessary "keymon" keymon
        runifnecessary "inputd" trimui_inputd
        runifnecessary "scened" trimui_scened
        runifnecessary "trimui_btmanager" trimui_btmanager
        runifnecessary "hardwareservice" hardwareservice
        
        # the next two lines are the contents of /usr/trimui/bin/premainui.sh. I moved them
        # here for greater transparency and control (e.g. what if another CSW modified those
        # files since NAND is writeable on the TrimUI devices?)
        rm -f /tmp/trimui_inputd/input_no_dpad
        rm -f /tmp/trimui_inputd/input_dpad_to_joystick
        
        touch /tmp/fbdisplay_exit
        cat /dev/zero > /dev/fb0
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"
        export LD_LIBRARY_PATH="/usr/trimui/lib"
        /mnt/SDCARD/spruce/scripts/iconfresh.sh

        if [ "$PLATFORM" = "Brick" ]; then
            DEVICE="TRIMUI_BRICK"
        else
            DEVICE="TRIMUI_SMART_PRO"
        fi

        cmd="/mnt/SDCARD/spruce/flip/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device $DEVICE \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"
            
        if [ $redirect_output -eq 1 ]; then
            # Redirect stdout/stderr to /dev/null
            sh -c "$cmd \"\$@\" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1" sh "$@"
        else
            # Run normally
            sh -c "$cmd \"\$@\"" sh "$@"
        fi

        if [ -f /tmp/trimui_inputd_restart ] ; then
            #restart before emulator run
            killall -9 trimui_inputd
            sleep 0.2
            runifnecessary "inputd" trimui_inputd
            rm /tmp/trimui_inputd_restart 
        fi
    ;;

    "Flip" )
        export LD_LIBRARY_PATH=/usr/miyoo/lib:$LD_LIBRARY_PATH
        insmod /lib/modules/rtk_btusb.ko
        runifnecessary "btmanager" /usr/miyoo/bin/btmanager
        runifnecessary "hardwareservice" /usr/miyoo/bin/hardwareservice
        runifnecessary "miyoo_inputd" /usr/miyoo/bin/miyoo_inputd
        cd /usr/miyoo/bin/
        export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
        /mnt/SDCARD/spruce/scripts/iconfresh.sh
        
        cmd="/mnt/SDCARD/spruce/flip/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device MIYOO_FLIP \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        if [ $redirect_output -eq 1 ]; then
            # Redirect stdout and stderr to /dev/null
            sh -c "$cmd \"\$@\" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1" sh "$@"
        else
            # Run normally (no redirection)
            sh -c "$cmd \"\$@\"" sh "$@"
        fi

    ;;
esac