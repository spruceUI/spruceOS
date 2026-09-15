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

    # handle swapped X/Y on RGB30. Can this be handled more gracefully by editing a gamecontrollerdb.txt?
    if [ "$PLATFORM" = "RGB30" ]; then
        sed -i -e 's/^OskKeyBksp=x/OskKeyBksp=y/' \
               -e 's/^OskKeyShift=y/OskKeyShift=x/' \
               -e 's/^KeyMenu=y/KeyMenu=x/' "$HOME/config.ini"
    else
        sed -i -e 's/^OskKeyBksp=y/OskKeyBksp=x/' \
               -e 's/^OskKeyShift=x/OskKeyShift=y/' \
               -e 's/^KeyMenu=x/KeyMenu=y/' "$HOME/config.ini"
    fi
fi

# GLES window on the Mali blob. The Miniloong Pocket 1 has the same GLES-only
# Mali-G52 as the RGB30, so it needs the same context or vtree fails to open one.
{ [ "$PLATFORM" = "RGB30" ] || [ "$PLATFORM" = "Miniloong" ]; } && export VTREE_GLES=1


case "$PLATFORM" in
    "A30")
        export LD_LIBRARY_PATH="$HOME/lib-A30:$LD_LIBRARY_PATH"
        killall -q -USR2 joystickinput
        ./vtree.a30 --rotate=3 >"$HOME/log.txt" 2>&1
        sync
        killall -q -USR2 joystickinput
        ;;
    "Brick"|"BrickPro"|"Flip"|"Miniloong"|"SmartPro"|"SmartProS"|"Pixel2"|"RGB30")
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
        export_sdl_gamecontroller_map positional
        ./vtree.aarch64 >"$HOME/log.txt" 2>&1
        sync
        ;;
    *)
        log_message "File Management: unsupported PLATFORM: $PLATFORM"
        exit 1
        ;;
esac
