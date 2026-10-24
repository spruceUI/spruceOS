#!/bin/sh
# Accent Color launcher. Spruce's Apps menu runs this through principal.sh after PyUI exits;
# PyUI restarts when it returns and loads the recoloured theme.
#
# The platform block mirrors App/Cheevos/launch.sh (itself a mirror of App/PyUI/launch.sh):
# the SDL libraries and drivers, the PyUI device name, the Python binary and the working
# directory PyUI uses on each platform.

# shellcheck source=/dev/null
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
STDERR_LOG="/tmp/accentcolor-stderr.log"
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
        # Mirror PyUI's menu audio setup: libpadsp sends /dev/dsp writes to audioserver.
        pidof audioserver >/dev/null || { audioserver >/dev/null 2>&1 & sleep 0.5; }
        export LD_PRELOAD="/mnt/SDCARD/miyoo/lib/libpadsp.so"
        freemma
        ACCENT_PYUI_DEVICE="$(get_miyoo_mini_variant)"
        ;;
    "A30")
        ln -s /dev/ttyS2 /dev/ttyS0 2>/dev/null
        CLEANUP="rm -f /dev/ttyS0"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/a30/sdl2"
        ACCENT_PYUI_DEVICE="MIYOO_A30"
        ;;
    "Flip")
        RUN_DIR="/usr/miyoo/bin"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        ACCENT_PYUI_DEVICE="MIYOO_FLIP"
        ;;
    "Brick" | "BrickPro" | "SmartPro" | "SmartProS")
        RUN_DIR="/usr/trimui/bin"
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        case "$PLATFORM" in
            "Brick") ACCENT_PYUI_DEVICE="TRIMUI_BRICK" ;;
            "BrickPro") ACCENT_PYUI_DEVICE="TRIMUI_BRICK_PRO" ;;
            "SmartProS") ACCENT_PYUI_DEVICE="TRIMUI_SMART_PRO_S" ;;
            *) ACCENT_PYUI_DEVICE="TRIMUI_SMART_PRO" ;;
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
            "AnbernicXX720480" | "AnbernicXX720480NoStick") ACCENT_PYUI_DEVICE="ANBERNIC_RGXX720480" ;;
            "AnbernicRG28XX") ACCENT_PYUI_DEVICE="ANBERNIC_RG28XX" ;;
            "AnbernicRGCubeXX") ACCENT_PYUI_DEVICE="ANBERNIC_RGCUBEXX" ;;
            *) ACCENT_PYUI_DEVICE="ANBERNIC_RGXX640480" ;;
        esac
        ;;
    "Miniloong" | "RGB30" | "RGB20SX" | "A10Mini" | "A10MiniV4" | "XUMiniM" | "G350" | "V10")
        # Every dArkMoss device, as in App/PyUI/launch.sh. Their PyUI device names don't
        # always match PLATFORM (V10 -> POWKIDDY_V10, A10Mini -> A10MINI, ...), so take
        # the name from device_names, the same source PyUI's launcher uses.
        export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
        export LD_LIBRARY_PATH="/mnt/SDCARD/App/PyUI/dll:/mnt/SDCARD/spruce/flip/lib:/usr/lib/aarch64-linux-gnu"
        export SDL_VIDEODRIVER=kmsdrm
        export SDL_AUDIODRIVER=alsa
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        ACCENT_PYUI_DEVICE="$(device_names | head -n 1)"
        ;;
    "Pixel2")
        RUN_DIR="/usr/bin"
        export PYSDL2_DLL_PATH="/usr/lib"
        PYTHON="/usr/bin/MainUI"
        ACCENT_PYUI_DEVICE="GKD_PIXEL2"
        ;;
    "Zero28" | "Zero40" | "XU20")
        RUN_DIR="/usr/magicx/bin"
        PYSDL2_DLL_PATH="$(magicx_pyui_sdl_dir)"
        export PYSDL2_DLL_PATH
        PYTHON="/mnt/SDCARD/spruce/flip/bin/MainUI"
        case "$PLATFORM" in
            "Zero40") ACCENT_PYUI_DEVICE="MAGICX_ZERO40" ;;
            "XU20") ACCENT_PYUI_DEVICE="MAGICX_XU20" ;;
            *) ACCENT_PYUI_DEVICE="MAGICX_ZERO28" ;;
        esac
        ;;
    *)
        log_message "Accent Color: platform $PLATFORM is not supported yet"
        show_message "Accent Color doesn't support this device ($PLATFORM) yet."
        exit 1
        ;;
esac

[ -n "$PYTHON" ] || PYTHON="$(get_python_path)"
export ACCENT_PYUI_DEVICE
export PLATFORM

cd "$RUN_DIR" || cd "$APP_DIR" || exit 1
"$PYTHON" "$APP_DIR/accent_picker.py" "$@" 2>"$STDERR_LOG"
STATUS=$?
[ -n "$CLEANUP" ] && $CLEANUP
if [ "$STATUS" -ne 0 ]; then
    # Errors before the app's own logging starts (e.g. an import error) only reach stderr:
    # keep them in the app log too, so the message points to one file with everything.
    LOG="/mnt/SDCARD/Saves/spruce/accentcolor-$PLATFORM.log"
    { echo "--- launch.sh: exit status $STATUS, stderr:"; cat "$STDERR_LOG"; } >>"$LOG" 2>/dev/null
    show_message "Accent Color couldn't start. Details: Saves/spruce/accentcolor-$PLATFORM.log"
fi
sync
exit "$STATUS"
