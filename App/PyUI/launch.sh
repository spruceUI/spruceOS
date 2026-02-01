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
button_listener_mode=0
for arg in "$@"; do
    if [ "$arg" = "-buttonListenerMode" ]; then
        redirect_output=0
        button_listener_mode=1
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

        cmd="/mnt/SDCARD/spruce/bin/python/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device MIYOO_A30 \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        # Convert command to positional args
        set -- $cmd "$@"

        log_message "Starting PyUI on $PLATFORM"
        if [ $button_listener_mode -eq 1 ]; then
            "$@"
        elif [ "$redirect_output" -eq 1 ]; then
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

        cd /usr/trimui/bin

        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"

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
        if [ $button_listener_mode -eq 1 ]; then
            "$@"
        elif [ "$redirect_output" -eq 1 ]; then
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
        if [ $button_listener_mode -eq 1 ]; then
            "$@"
        elif [ "$redirect_output" -eq 1 ]; then
            "$@" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1
        else
            "$@" >/dev/null 2>&1
        fi
    ;;
############################################################
# Miyoo Mini Flip
############################################################
    "MiyooMini" )

        skip_freemma=0
        redirect_output=1

        for arg in "$@"; do
            if [ "$arg" = "-buttonListenerMode" ]; then
                skip_freemma=1
                redirect_output=0
                break
            fi
        done

        export PATH="/mnt/SDCARD/spruce/miyoomini/bin:$PATH"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/miyoomini/lib"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/bin/python/lib:$LD_LIBRARY_PATH"

        export SDL_VIDEODRIVER=mmiyoo
        export SDL_AUDIODRIVER=mmiyoo
        export EGL_VIDEODRIVER=mmiyoo
        export SDL_MMIYOO_DOUBLE_BUFFER=1

        if [ $skip_freemma -eq 0 ]; then
            freemma
        fi

        miyoo_device=$(get_miyoo_mini_variant)
        
        cmd="/mnt/SDCARD/spruce/bin/python/bin/MainUI \
                /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
                -device $miyoo_device \
                -logDir /mnt/SDCARD/Saves/spruce \
                -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
                -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        set -- $cmd "$@"

        log_message "Starting PyUI on $PLATFORM"

        if [ $button_listener_mode -eq 1 ]; then
            "$@"
        elif [ "$redirect_output" -eq 1 ]; then
            "$@" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1
        else
            "$@" >/dev/null 2>&1
        fi


    ;;
############################################################
# GKD Pixel 2
############################################################
    "Pixel2" )
        redirect_output=0
        cd /usr/bin/
        export PYSDL2_DLL_PATH="/usr/lib"

        cmd="/mnt/SDCARD/spruce/pixel2/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device GKD_PIXEL2 \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json"

        set -- $cmd "$@"

        log_message "Starting PyUI on $PLATFORM"
        if [ $button_listener_mode -eq 1 ]; then
            "$@"
        elif [ "$redirect_output" -eq 1 ]; then
            "$@" >> /mnt/SDCARD/App/PyUI/run.txt 2>&1
        else
            "$@" >/dev/null 2>&1
        fi
    ;;
esac
