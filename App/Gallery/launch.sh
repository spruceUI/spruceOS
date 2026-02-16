#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export HOME="$(dirname "$0")"
cd "$HOME"

if [ "$PLATFORM" = "MiyooMini" ]; then
    cp config_mini.conf config.conf

    sed -i "s/SCREEN_W/${DISPLAY_WIDTH}/" config.conf
    sed -i "s/SCREEN_H/${DISPLAY_HEIGHT}/" config.conf

    export LD_LIBRARY_PATH="$HOME/lib32:$LD_LIBRARY_PATH"
    ./gallery32 > gallery.log
else
    cp config_all.conf config.conf
    
    sed -i "s/SCREEN_W/${DISPLAY_WIDTH}/" config.conf
    sed -i "s/SCREEN_H/${DISPLAY_HEIGHT}/" config.conf

    export LD_LIBRARY_PATH="$HOME/lib64:$LD_LIBRARY_PATH"

    if [ "$PLATFORM" = "Pixel2" ]; then
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./galleryPixel2.gptk" &
    else
        /mnt/SDCARD/spruce/bin64/gptokeyb -c "./gallery.gptk" &
    fi
    
    sleep 0.3
    ./gallery64 > gallery.log
    sync
    kill -9 "$(pidof gptokeyb)" 
fi
