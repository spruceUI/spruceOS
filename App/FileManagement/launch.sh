#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# darkmoss devices have the X and Y buttons swapped compared to the rest of the family. This function swaps them in config.ini so that vtree sees them correctly.
swap_x_and_y_buttons() {
    if [ -f "$HOME/config.ini" ]; then
        sed -i -e 's/^OskKeyBksp=x/OskKeyBksp=y/' \
                -e 's/^OskKeyShift=y/OskKeyShift=x/' \
                -e 's/^KeyMenu=y/KeyMenu=x/' "$HOME/config.ini"
    fi
}

restore_x_and_y_buttons() {
    if [ -f "$HOME/config.ini" ]; then
        sed -i -e 's/^OskKeyBksp=y/OskKeyBksp=x/' \
                -e 's/^OskKeyShift=x/OskKeyShift=y/' \
                -e 's/^KeyMenu=x/KeyMenu=y/' "$HOME/config.ini"
    fi
}


# Disable idle/shutdown timer while file manager is open
killall -q idlemon 2>/dev/null
killall -q idle_watchdog.sh 2>/dev/null

export HOME="$(dirname "$0")"
cd "$HOME"

LOG_PATH="/mnt/SDCARD/Saves/spruce/vtree-${PLATFORM}.log"

# Force vtree to re-auto-detect screen res every launch (config.ini is shared
# across devices but the saved dims would be stale if you swap cards between
# Brick/TSPS/Flip/etc.). Other settings (theme, keybinds) are preserved.
if [ -f "$HOME/config.ini" ]; then
    sed -i -e 's/^ScreenWidth=.*/ScreenWidth=0/' \
           -e 's/^ScreenHeight=.*/ScreenHeight=0/' \
           -e 's/^Rotation=.*/Rotation=0/' "$HOME/config.ini"
fi

case "$PLATFORM_FAMILY" in
    "darkmoss")
        swap_x_and_y_buttons
        export VTREE_GLES=1
        ;;
    "h700")
        restore_x_and_y_buttons
        export_sdl_gamecontroller_map positional
        ;;
    *)
        restore_x_and_y_buttons
        ;;
esac

case "$PLATFORM" in
    "A30")
        export LD_LIBRARY_PATH="$HOME/lib-A30:$LD_LIBRARY_PATH"
        killall -q -USR2 joystickinput
        ./vtree.a30 --rotate=3 >"$LOG_PATH" 2>&1
        killall -q -USR2 joystickinput
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
        ./vtree.mini >"$LOG_PATH" 2>&1
        ;;
    *)
        ./vtree.aarch64 >"$LOG_PATH" 2>&1
        ;;
esac

sync
