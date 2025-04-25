#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
    /mnt/SDCARD/App/Credits/credits_app.elf \
    /mnt/SDCARD/App/Credits/sprucepixelbg43.png \
    /mnt/SDCARD/App/Credits/credits.txt \
    /mnt/SDCARD/Themes/SPRUCE/nunwen.ttf 22 \
    "/mnt/SDCARD/App/Credits/Sweater Ass Sounding Ass.mp3" \
    "/mnt/SDCARD/App/Credits/3 - Sir Daniel Bonaduce.mp3"
else
    [ "$PLATFORM" = "Flip" ] && /mnt/SDCARD/spruce/bin64/gptokeyb -k "as" -c "./as.gptk" & 
    [ "$PLATFORM" = "Flip" ] && sleep 0.5

    /mnt/SDCARD/App/Credits/credits_app \
    /mnt/SDCARD/App/Credits/sprucepixelbg43.png \
    /mnt/SDCARD/App/Credits/credits.txt \
    /mnt/SDCARD/Themes/SPRUCE/nunwen.ttf 22 \
    "/mnt/SDCARD/App/Credits/Sweater Ass Sounding Ass.mp3" \
    "/mnt/SDCARD/App/Credits/3 - Sir Daniel Bonaduce.mp3"

    [ "$PLATFORM" = "Flip" ] && kill -9 "$(pidpf gptokeyb)"

fi