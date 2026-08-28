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

[ "$PLATFORM" = "RGB30" ] && export VTREE_GLES=1  # GLES window on the Mali blob

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
        # Nothing on this device ships an SDL GameController mapping for
        # "ANBERNIC-keys", so without one the pad enumerates and nothing
        # responds. Positional rather than the default label-named form: vtree
        # carries spruce's nintendo-button-labels patch and already swaps A<->B
        # and X<->Y itself, so the label-named map corrected twice and landed
        # back where it started. See export_sdl_gamecontroller_map in
        # helperFunctions.sh for what the two forms mean.
        export_sdl_gamecontroller_map positional
        ./vtree.aarch64 >"$HOME/log.txt" 2>&1
        sync
        ;;
    *)
        echo "File Management: unsupported PLATFORM=$PLATFORM" >&2
        exit 1
        ;;
esac
