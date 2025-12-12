#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

runifnecessary() {
    a=$(pgrep "$1")
    if [ "$a" = "" ] ; then
        $2 &
    fi
}

# Check for -buttonListenerMode in arguments
redirect_output=0
for arg in "$@"; do
    if [ "$arg" = "-buttonListenerMode" ]; then
        redirect_output=0
        break
    fi
done

# Launch (and subsequently close) MainUI with various quirks depending on PLATFORM
case "$PLATFORM" in

############################################################
# A30
############################################################
    "A30" )
        ln -s /dev/ttyS2 /dev/ttyS0

        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/a30/sdl2"
        export LD_LIBRARY_PATH="/mnt/SDCARD/miyoo/lib:/usr/miyoo/lib:/usr/lib:/lib"

        cmd="/mnt/SDCARD/spruce/bin/python/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device MIYOO_A30 \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        # Convert command to positional args
        set -- $cmd "$@"

        log_message "Starting PyUI on $PLATFORM"
        if [ "$redirect_output" -eq 1 ]; then
            "$@" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1
        else
            "$@" >/dev/null 2>&1
        fi

        rm /dev/ttyS0
    ;;

############################################################
# Brick / SmartPro / SmartProS
############################################################
    "Brick" | "SmartPro" | "SmartProS" )
        tinymix set 9 1
        tinymix set 1 0

        export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH
        cd /usr/trimui/bin

        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"
        export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"

        if [ "$PLATFORM" = "Brick" ]; then
            DEVICE="TRIMUI_BRICK"
        elif [ "$PLATFORM" = "SmartProS" ]; then
            DEVICE="TRIMUI_SMART_PRO_S"
        else
            DEVICE="TRIMUI_SMART_PRO"
        fi

        cmd="/mnt/SDCARD/spruce/flip/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device $DEVICE \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        # Convert to positional args
        set -- $cmd "$@"

        log_message "Starting PyUI on $PLATFORM"
        if [ "$redirect_output" -eq 1 ]; then
            "$@" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1
        else
            "$@" >/dev/null 2>&1
        fi

        if [ -f /tmp/trimui_inputd_restart ] ; then
            killall -9 trimui_inputd
            sleep 0.2
            runifnecessary "inputd" trimui_inputd
            rm /tmp/trimui_inputd_restart 
        fi
    ;;

############################################################
# Miyoo Flip
############################################################
    "Flip" )
        export LD_LIBRARY_PATH=/usr/miyoo/lib:/usr/lib:/lib
        cd /usr/miyoo/bin/
        export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"

        cmd="/mnt/SDCARD/spruce/flip/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device MIYOO_FLIP \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        set -- $cmd "$@"

        log_message "Starting PyUI on $PLATFORM"
        if [ "$redirect_output" -eq 1 ]; then
            "$@" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1
        else
            "$@" >/dev/null 2>&1
        fi
    ;;
esac
