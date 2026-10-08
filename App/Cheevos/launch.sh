#!/bin/sh
# Cheevos launcher. Spruce's Apps menu runs this through principal.sh after PyUI exits;
# PyUI restarts when it returns.
#
# Each branch mirrors the matching branch of App/PyUI/launch.sh (SpruceOS 4.5.0+): the SDL
# libraries and drivers, the PyUI device name, the Python binary and the working directory
# PyUI uses on that platform. Only the Miyoo Mini family has been tested on hardware. If the
# app can't start, or the platform is unknown, a message is shown through PyUI's own launcher, which knows every
# platform Spruce supports.

# shellcheck source=/dev/null
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
STDERR_LOG="/tmp/cheevos-stderr.log"
PYTHON=""
RUN_DIR="$APP_DIR"
CLEANUP=""

# Show a message with PyUI's own launcher (it sets up the display for every platform).
show_message() {
    /mnt/SDCARD/App/PyUI/launch.sh -msgDisplay "$1" -msgDisplayTimeMs 5000
}

# PLATFORM comes from helperFunctions.sh.
# shellcheck disable=SC2154
case "$PLATFORM" in
    "MiyooMini")
        export PATH="/mnt/SDCARD/spruce/miyoomini/bin:$PATH"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/miyoomini/lib"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/bin/python/lib:$LD_LIBRARY_PATH"
        export SDL_VIDEODRIVER=mmiyoo
        export SDL_AUDIODRIVER=mmiyoo
        export EGL_VIDEODRIVER=mmiyoo
        export SDL_MMIYOO_DOUBLE_BUFFER=1
        freemma
        CHEEVOS_PYUI_DEVICE="$(get_miyoo_mini_variant)"
        ;;
    "A30")
        ln -s /dev/ttyS2 /dev/ttyS0 2>/dev/null
        CLEANUP="rm -f /dev/ttyS0"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/a30/sdl2"
        CHEEVOS_PYUI_DEVICE="MIYOO_A30"
        ;;
    "Flip")
        RUN_DIR="/usr/miyoo/bin"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        CHEEVOS_PYUI_DEVICE="MIYOO_FLIP"
        ;;
    "Brick" | "BrickPro" | "SmartPro" | "SmartProS")
        RUN_DIR="/usr/trimui/bin"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        case "$PLATFORM" in
            "Brick") CHEEVOS_PYUI_DEVICE="TRIMUI_BRICK" ;;
            "BrickPro") CHEEVOS_PYUI_DEVICE="TRIMUI_BRICK_PRO" ;;
            "SmartProS") CHEEVOS_PYUI_DEVICE="TRIMUI_SMART_PRO_S" ;;
            *) CHEEVOS_PYUI_DEVICE="TRIMUI_SMART_PRO" ;;
        esac
        ;;
    "AnbernicXX720480" | "AnbernicXX720480NoStick" | "AnbernicXX640480" | \
        "AnbernicXX640480NoStick" | "AnbernicXX640480OneStick" | "AnbernicRG28XX" | \
        "AnbernicRGCubeXX")
        PYUI_DLL=/mnt/SDCARD/App/PyUI/dll
        [ -f /mnt/SDCARD/App/PyUI/dll-mali/libSDL2-2.0.so.0 ] && PYUI_DLL=/mnt/SDCARD/App/PyUI/dll-mali
        export PYSDL2_DLL_PATH="$PYUI_DLL"
        export LD_LIBRARY_PATH="$PYUI_DLL:/mnt/SDCARD/spruce/flip/lib:/usr/lib"
        export SDL_JOYSTICK_DISABLE_UDEV=1
        case "$PYUI_DLL" in
            *dll-mali) export SDL_VIDEODRIVER=mali ;;
        esac
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        case "$PLATFORM" in
            "AnbernicXX720480" | "AnbernicXX720480NoStick") CHEEVOS_PYUI_DEVICE="ANBERNIC_RGXX720480" ;;
            "AnbernicRG28XX") CHEEVOS_PYUI_DEVICE="ANBERNIC_RG28XX" ;;
            "AnbernicRGCubeXX") CHEEVOS_PYUI_DEVICE="ANBERNIC_RGCUBEXX" ;;
            *) CHEEVOS_PYUI_DEVICE="ANBERNIC_RGXX640480" ;;
        esac
        ;;
    "Miniloong" | "RGB30" | "RGB20SX")
        export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
        export LD_LIBRARY_PATH="/mnt/SDCARD/App/PyUI/dll:/mnt/SDCARD/spruce/flip/lib:/usr/lib/aarch64-linux-gnu"
        export SDL_VIDEODRIVER=kmsdrm
        export SDL_AUDIODRIVER=alsa
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        if [ "$PLATFORM" = "Miniloong" ]; then
            CHEEVOS_PYUI_DEVICE="MINILOONG_POCKET1"
        else
            CHEEVOS_PYUI_DEVICE="$PLATFORM"
        fi
        ;;
    "Pixel2")
        RUN_DIR="/usr/bin"
        export PYSDL2_DLL_PATH="/usr/lib"
        PYTHON="/usr/bin/MainUI"
        CHEEVOS_PYUI_DEVICE="GKD_PIXEL2"
        ;;
    "Zero28" | "Zero40" | "XU20")
        RUN_DIR="/usr/magicx/bin"
        PYSDL2_DLL_PATH="$(magicx_pyui_sdl_dir)"
        export PYSDL2_DLL_PATH
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        case "$PLATFORM" in
            "Zero40") CHEEVOS_PYUI_DEVICE="MAGICX_ZERO40" ;;
            "XU20") CHEEVOS_PYUI_DEVICE="MAGICX_XU20" ;;
            *) CHEEVOS_PYUI_DEVICE="MAGICX_ZERO28" ;;
        esac
        ;;
    *)
        log_message "Cheevos: platform $PLATFORM is not supported yet"
        show_message "Cheevos doesn't support this device ($PLATFORM) yet."
        exit 1
        ;;
esac

[ -n "$PYTHON" ] || PYTHON="$(get_python_path)"
export CHEEVOS_PYUI_DEVICE
export PLATFORM
export PYTHONPATH="$APP_DIR"
export SSL_CERT_FILE=/mnt/SDCARD/spruce/etc/ca-certificates.crt

cd "$RUN_DIR" || cd "$APP_DIR" || exit 1
"$PYTHON" -m cheevos 2>"$STDERR_LOG"
STATUS=$?
[ -n "$CLEANUP" ] && $CLEANUP
if [ "$STATUS" -ne 0 ]; then
    # Errors before the app's own logging starts (e.g. an import error) only reach stderr:
    # keep them in the app log too, so the message points to one file with everything.
    LOG="/mnt/SDCARD/Saves/spruce/cheevos-$PLATFORM.log"
    { echo "--- launch.sh: exit status $STATUS, stderr:"; cat "$STDERR_LOG"; } >>"$LOG" 2>/dev/null
    show_message "Cheevos couldn't start. Details: Saves/spruce/cheevos-$PLATFORM.log"
fi
exit "$STATUS"
