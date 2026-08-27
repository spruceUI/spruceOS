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
    "Brick" | "BrickPro" | "SmartPro" | "SmartProS" )
        tinymix set 9 1
        tinymix set 1 0

        cd /usr/trimui/bin

        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"

        if [ "$PLATFORM" = "Brick" ]; then
            DEVICE="TRIMUI_BRICK"
        elif [ "$PLATFORM" = "BrickPro" ]; then
            DEVICE="TRIMUI_BRICK_PRO"
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
# Anbernic RG XX line (Allwinner H700)
############################################################
    "AnbernicXX720480" | "AnbernicXX640480" | "AnbernicRG28XX" | "AnbernicRGCubeXX" )
        # BaseOS ships no SDL2 and no python: use the aarch64 pair we already
        # bundle. MainUI is the bind-mounted alias of python3.10 set up in
        # device_init - spruce greps for that process name.
        #
        # Our usual SDL2 only speaks KMSDRM and wayland. BaseOS has neither
        # libdrm/libgbm nor wayland - its mali blob is the fbdev winsys build -
        # so that SDL2 falls back to the dummy driver and renders nowhere.
        # Prefer a mali-fbdev SDL2 when one is staged alongside.
        PYUI_DLL=/mnt/SDCARD/App/PyUI/dll
        [ -f /mnt/SDCARD/App/PyUI/dll-mali/libSDL2-2.0.so.0 ] && PYUI_DLL=/mnt/SDCARD/App/PyUI/dll-mali

        export PYSDL2_DLL_PATH="$PYUI_DLL"
        export LD_LIBRARY_PATH="$PYUI_DLL:/mnt/SDCARD/spruce/flip/lib:/usr/lib"
        PYUI_BIN=/mnt/SDCARD/spruce/flip/bin/MainUI

        # BaseOS runs no udev and no mdev - devtmpfs creates the nodes and
        # nothing else is listening. SDL's joystick layer goes looking for
        # udev during SDL_Init and hangs there, which strands PyUI before it
        # ever opens the display. BaseOS documents this and NextUI sets the
        # same variable.
        export SDL_JOYSTICK_DISABLE_UDEV=1

        # Name the driver rather than letting SDL probe: the mali build is
        # the only backend on this box that can reach the panel, and a
        # failure to select it should be a loud error, not a silent
        # fallback to dummy.
        case "$PYUI_DLL" in
            *dll-mali) export SDL_VIDEODRIVER=mali ;;
        esac

        if [ "$PLATFORM" = "AnbernicXX720480" ]; then
            DEVICE="ANBERNIC_RGXX720480"
        elif [ "$PLATFORM" = "AnbernicRG28XX" ]; then
            DEVICE="ANBERNIC_RG28XX"
        elif [ "$PLATFORM" = "AnbernicXX640480" ]; then
            DEVICE="ANBERNIC_RGXX640480"
        elif [ "$PLATFORM" = "AnbernicRGCubeXX" ]; then
            DEVICE="ANBERNIC_RGCUBEXX"
        else
            DEVICE="ANBERNIC_RGXX640480"
        fi

        "$PYUI_BIN" \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device "$DEVICE" \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json  "$@"

    ;;

############################################################
# Powkiddy RGB30 (Rockchip RK3566, under MossySpruce)
############################################################
    "RGB30" )
        # Unlike BaseOS, MossySpruce is a full glibc 2.38 distro that already
        # provides libdrm, mesa and a KMSDRM SDL2, which is the backend our own
        # bundled SDL2 was built for. So the mali-fbdev dance the H700 line
        # needs does not apply here - use our normal dll.
        export PYSDL2_DLL_PATH=/mnt/SDCARD/App/PyUI/dll
        # /usr/lib/aarch64-linux-gnu, not /usr/lib: on Debian aarch64 that is
        # where libEGL, libgbm and libMali actually live.
        export LD_LIBRARY_PATH="/mnt/SDCARD/App/PyUI/dll:/mnt/SDCARD/spruce/flip/lib:/usr/lib/aarch64-linux-gnu"

        # MinUI's own launcher sets these on this hardware, which is the best
        # evidence available that they are the working combination.
        export SDL_VIDEODRIVER=kmsdrm
        export SDL_AUDIODRIVER=alsa

        log_message "Starting PyUI on $PLATFORM"
        /mnt/SDCARD/spruce/flip/bin/MainUI \
            /mnt/SDCARD/App/PyUI/main-ui/mainui.py \
            -device RGB30 \
            -logDir /mnt/SDCARD/Saves/spruce \
            -pyUiConfig /mnt/SDCARD/App/PyUI/py-ui-config.json \
            -cfwConfig /mnt/SDCARD/Saves/spruce/spruce-config.json  "$@"

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

        cmd="/usr/bin/MainUI \
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

############################################################
# MagicX Zero28
############################################################

    "Zero28" )

        cd /usr/magicx/bin
        export PYSDL2_DLL_PATH="/usr/magicx/lib"
        DEVICE="MAGICX_ZERO28"

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
    ;;

esac
