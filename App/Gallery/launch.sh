#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export HOME="$(dirname "$0")"
cd "$HOME"

if [ "$PLATFORM" = "MiyooMini" ]; then
    cp config_mini.conf config.conf

    sed -e "s/SCREEN_W/${DISPLAY_WIDTH}/" -e "s/SCREEN_H/${DISPLAY_HEIGHT}/" config.conf > config.conf.tmp && mv config.conf.tmp config.conf

    export LD_LIBRARY_PATH="$HOME/lib32:$LD_LIBRARY_PATH"
    ./gallery32 > gallery.log
else
    cp config_all.conf config.conf
    
    sed -e "s/SCREEN_W/${DISPLAY_WIDTH}/" -e "s/SCREEN_H/${DISPLAY_HEIGHT}/" config.conf > config.conf.tmp && mv config.conf.tmp config.conf

    export LD_LIBRARY_PATH="$HOME/lib64:$LD_LIBRARY_PATH"

    # gallery64 links libSDL_image-1.2 and libSDL_ttf-2.0 - SDL 1.2 era - but
    # lib64/ here only carries libSDL-1.2 itself. The other aarch64 devices get
    # those two from their firmware; BaseOS has neither, and nor does the stock
    # Anbernic image, so the loader fails before any code runs.
    #
    # They come from spruce/h700/lib64, shared with the E-Reader, which needs
    # exactly the same set. That directory is never on a global path - only the
    # XX app launchers that need it prepend it - so it cannot shadow the
    # firmware copies on Brick, Flip or SmartPro.
    case "$PLATFORM" in
        "Anbernic"*)
            export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/h700/lib64:$LD_LIBRARY_PATH"

            # gptokeyb reads the pad through SDL_GameController, and without a
            # mapping it sees a plain joystick and translates nothing - gallery
            # gets no keys and the app looks frozen.
            #
            # Positional rather than the default label-named form: gallery.gptk
            # speaks SDL's own vocabulary, where "a" is the South button, and on
            # the other devices SDL gets that from a stock mapping which is
            # positional. The label-named map would put every binding in the
            # .gptk on the wrong physical key.
            export_sdl_gamecontroller_map positional
            ;;
    esac

    if [ "$PLATFORM" = "Pixel2" ]; then
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./galleryPixel2.gptk" &
    else
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./gallery.gptk" &
    fi

    sleep 0.3

    # gallery64's libSDL-1.2 is sdl12-compat, so the keys gptokeyb injects
    # arrive through SDL2's evdev backend. That SDL2 is built without libudev,
    # and BaseOS runs no udevd anyway, so it has no reliable way to discover the
    # virtual keyboard gptokeyb creates. SDL_EVDEV_DEVICES names the node
    # outright and skips discovery; the node number is not fixed, so find it by
    # the name gptokeyb gives it.
    case "$PLATFORM" in
        "Anbernic"*)
            if [ -n "$SPRUCE_BASEOS" ]; then
                i=0
                while [ "$i" -lt 20 ]; do
                    for d in /sys/class/input/event*; do
                        [ -r "$d/device/name" ] || continue
                        if [ "$(cat "$d/device/name" 2>/dev/null)" = "Fake Keyboard" ]; then
                            export SDL_EVDEV_DEVICES="/dev/input/$(basename "$d")"
                            break
                        fi
                    done
                    [ -n "$SDL_EVDEV_DEVICES" ] && break
                    i=$((i + 1))
                    sleep 0.1
                done
            fi
            ;;
    esac

    # gallery64 gets its own SDL2, and only gallery64. Everything - drawing and
    # keys - goes through SDL2 underneath sdl12-compat. The mali-fbdev SDL2 in
    # dll-mali draws fine but never delivers the keystrokes gptokeyb injects:
    # its only evdev pump is DUMMY_EVDEV_Poll, wired to the dummy video driver,
    # and gallery64 needs mali because it has no framebuffer code of its own.
    # This 2.0.12 build is the stock Anbernic vendor's own, which has both the
    # mali video driver and the generic SDL_EVDEV_Poll.
    #
    # gptokeyb deliberately keeps dll-mali: it needs to *see* the pad, and only
    # that build carries NextUI's H700 joystick classification patch. So the two
    # processes run on different SDL2s, which is why this is scoped to the
    # command rather than exported.
    case "$PLATFORM" in
        "Anbernic"*)
            if [ -n "$SPRUCE_BASEOS" ] && [ -f /mnt/SDCARD/spruce/h700/lib64/sdl2/libSDL2-2.0.so.0 ]; then
                LD_LIBRARY_PATH=/mnt/SDCARD/spruce/h700/lib64/sdl2:$LD_LIBRARY_PATH ./gallery64 > gallery.log
            else
                ./gallery64 > gallery.log
            fi
            ;;
        *)
            ./gallery64 > gallery.log
            ;;
    esac
    sync
    kill -9 "$(pidof gptokeyb)"
fi
