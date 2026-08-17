#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Disable idle/shutdown timer while file manager is open
killall -q idlemon 2>/dev/null
killall -q idlemon_mm.sh 2>/dev/null

export HOME="$(dirname "$0")"
cd "$HOME"

# Force vtree to re-auto-detect screen res every launch (config.ini is shared
# across devices but the saved dims would be stale if you swap cards between
# Brick/TSPS/Flip/etc.). Other settings (theme, keybinds) are preserved.
if [ -f "$HOME/config.ini" ]; then
    sed -i -e 's/^ScreenWidth=.*/ScreenWidth=0/' \
           -e 's/^ScreenHeight=.*/ScreenHeight=0/' \
           -e 's/^Rotation=.*/Rotation=0/' "$HOME/config.ini"
fi

case "$PLATFORM" in
    "SmartPro"* | "BrickPro") export LD_LIBRARY_PATH="$HOME/lib-${PLATFORM}:$HOME/lib-Brick:$LD_LIBRARY_PATH" ;;
    * )           export LD_LIBRARY_PATH="$HOME/lib-${PLATFORM}:$LD_LIBRARY_PATH" ;;
esac

case "$PLATFORM" in
    "A30")
        killall -q -USR2 joystickinput
        ./vtree.a30 --rotate=3 >"$HOME/log.txt" 2>&1
        sync
        killall -q -USR2 joystickinput
        ;;
    "Brick"|"BrickPro"|"Flip"|"SmartPro"|"SmartProS"|"Pixel2")
        ./vtree.aarch64 >"$HOME/log.txt" 2>&1
        sync
        ;;
    "MiyooMini")
        # freemma releases the display from PyUI before vtree takes over.
        export PATH="/mnt/SDCARD/spruce/miyoomini/bin:$PATH"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/miyoomini/lib:$LD_LIBRARY_PATH"
        export SDL_VIDEODRIVER=mmiyoo
        export SDL_AUDIODRIVER=mmiyoo
        export EGL_VIDEODRIVER=mmiyoo
        export SDL_MMIYOO_DOUBLE_BUFFER=1
        freemma
        ./vtree.mini >"$HOME/log.txt" 2>&1
        sync
        ;;
    "Anbernic"*)
        if [ -n "$SPRUCE_BASEOS" ]; then
            # Stock borrows Anbernic's own DinguxCommander off the vendor
            # partition. BaseOS replaces the userland and drops /mnt/vendor
            # entirely, so that binary does not exist and this app was dead.
            #
            # vtree.aarch64 runs here as-is: all six of its NEEDED libraries
            # resolve - libSDL2 from App/PyUI/dll-mali, libSDL2_ttf and
            # libSDL2_image from the same directory, and libc/libm/loader from
            # BaseOS's own harvest - and its glibc floor is 2.17, well under
            # the 2.35 BaseOS keeps from the stock image.
            #
            # No --rotate, unlike the A30: PyUI reports screen_rotation 0 for
            # the RG28XX under BaseOS, so the framebuffer is already the right
            # way up by the time an app sees it. Note the shell-side
            # DISPLAY_ROTATION is still 270 for that model, which is a wider
            # inconsistency rather than something for this app to work around.
            ./vtree.aarch64 >"$HOME/log.txt" 2>&1
            sync
        else
            cd "/mnt/vendor/bin/fileM"
            /mnt/vendor/bin/fileM/dinguxCommand_en.dge
        fi
        ;;
    *)
        echo "File Management: unsupported PLATFORM=$PLATFORM" >&2
        exit 1
        ;;
esac
