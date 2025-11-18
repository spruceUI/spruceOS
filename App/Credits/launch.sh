#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
HERE="$(dirname "$0")"
cd "$HERE"

if [ "$PLATFORM" = "A30" ]; then
    "$HERE"/credits_app.elf \
    "$HERE"/sprucepixelbg43.png \
    "$HERE"/credits.txt \
    /mnt/SDCARD/Themes/SPRUCE/nunwen.ttf 22 \
    "$HERE"/Sweater Ass Sounding Ass.mp3" \
    "$HERE"/3 - Sir Daniel Bonaduce.mp3"
else
    [ "$PLATFORM" = "Flip" ] && /mnt/SDCARD/spruce/bin64/gptokeyb -k "credits_app" -c "./credits_app.gptk" & 
    [ "$PLATFORM" = "Flip" ] && sleep 0.5

    "$HERE"/credits_app \
    "$HERE"/sprucepixelbg43.png \
    "$HERE"/credits.txt \
    /mnt/SDCARD/Themes/SPRUCE/nunwen.ttf 22 \
    "$HERE"/Sweater Ass Sounding Ass.mp3" \
    "$HERE"/3 - Sir Daniel Bonaduce.mp3" 

    [ "$PLATFORM" = "Flip" ] && kill -9 "$(pidof gptokeyb)"
fi