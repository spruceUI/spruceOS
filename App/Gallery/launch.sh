#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export HOME="$(dirname "$0")"
cd "$HOME"

LOG_PATH="/mnt/SDCARD/Saves/spruce/gallery-${PLATFORM}.log"


# Miyoo Mini is not enabled for this app in the config.json; should it be?
# A30 is also notably missing from both this script and the json.
if [ "$PLATFORM" = "MiyooMini" ]; then
    cp config_mini.conf config.conf

    sed -e "s/SCREEN_W/${DISPLAY_WIDTH}/" -e "s/SCREEN_H/${DISPLAY_HEIGHT}/" config.conf > config.conf.tmp && mv config.conf.tmp config.conf

    export LD_LIBRARY_PATH="$HOME/lib32:$LD_LIBRARY_PATH"
    ./gallery32  > "$LOG_PATH" 2>&1
else
    cp config_all.conf config.conf
    
    sed -e "s/SCREEN_W/${DISPLAY_WIDTH}/" -e "s/SCREEN_H/${DISPLAY_HEIGHT}/" config.conf > config.conf.tmp && mv config.conf.tmp config.conf

    export LD_LIBRARY_PATH="$HOME/lib64:$LD_LIBRARY_PATH"

    # gallery64 needs libSDL_image-1.2 and libSDL_ttf-2.0, absent from its
    # lib64/ and from BaseOS/stock Anbernic firmware. Use the copies shared
    # with E-Reader under spruce/h700/lib64, scoped here so they don't shadow
    # firmware libraries on Brick, Flip or SmartPro.
    case "$PLATFORM_FAMILY" in
        "h700")
            export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/h700/lib64:$LD_LIBRARY_PATH"
            # gptokeyb needs a GameController mapping to translate pad input.
            # Use positional mapping: gallery.gptk uses SDL names ("a" = South),
            # matching the stock mappings on other devices; label-named mapping
            # would bind its controls to the wrong physical buttons.
            export_sdl_gamecontroller_map positional
            ;;
        "darkmoss")
            export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/h700/lib64:$LD_LIBRARY_PATH"
            ;;
    esac

    if [ "$PLATFORM" = "Pixel2" ]; then
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./galleryPixel2.gptk" &
    else
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./gallery.gptk" &
    fi

    sleep 0.3

    # gallery64 uses sdl12-compat, so drawing and injected keys go through SDL2.
    # BaseOS has no udevd, and its SDL2 lacks libudev; locate gptokeyb's virtual
    # keyboard by name and set SDL_EVDEV_DEVICES to bypass discovery.
    #
    # Run gallery64 with the vendor SDL2 build: it supports both Mali video
    # (gallery has no framebuffer backend) and generic SDL_EVDEV_Poll. Keep
    # gptokeyb on dll-mali, which has NextUI's H700 joystick classification
    # patch. Scope the alternate SDL2 to gallery64 so it can't affect gptokeyb.
    case "$PLATFORM_FAMILY" in
        "h700")
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

            LD_LIBRARY_PATH=/mnt/SDCARD/spruce/h700/lib64/sdl2:$LD_LIBRARY_PATH ./gallery64 > "$LOG_PATH" 2>&1
            ;;
        *)
            ./gallery64 > "$LOG_PATH" 2>&1
            ;;
    esac

    sync
    kill -9 "$(pidof gptokeyb)" 2>/dev/null
fi
