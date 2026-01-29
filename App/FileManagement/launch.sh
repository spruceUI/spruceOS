#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export HOME="$(dirname "$0")"
cd "$HOME"

case "$PLATFORM" in
    "SmartPro"* | "Pixel2" ) export LD_LIBRARY_PATH="$HOME/lib-Brick:$LD_LIBRARY_PATH" ;;
    * )          export LD_LIBRARY_PATH="$HOME/lib-${PLATFORM}:$LD_LIBRARY_PATH" ;;
esac

if [ "$PLATFORM" = "A30" ]; then
	killall -q -USR2 joystickinput   # set stick to d-pad mode
	./DinguxCommanderA30
	sync
	killall -q -USR2 joystickinput   # set stick to d-pad mode

elif [ "$PLATFORM" = "SmartProS" ]; then
    /mnt/SDCARD/spruce/bin64/gptokeyb -c "./DinguxCommander.gptk" &
    sleep 0.3
	./"DinguxCommanderSmartPro"
    sync
    kill -9 "$(pidof gptokeyb)"

elif [ "$PLATFORM" = "Pixel2" ]; then
    /mnt/SDCARD/spruce/bin64/gptokeyb -c "./DinguxCommanderPixel2.gptk" &
    sleep 0.3
	./"DinguxCommanderFlip"
    sync
    kill -9 "$(pidof gptokeyb)"

else
    /mnt/SDCARD/spruce/bin64/gptokeyb -c "./DinguxCommander.gptk" &
    sleep 0.3
	./"DinguxCommander$PLATFORM"
    sync
    kill -9 "$(pidof gptokeyb)" 
fi
