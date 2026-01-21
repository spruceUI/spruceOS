#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
	export LD_LIBRARY_PATH=$(dirname "$0")/libs32:/mnt/SDCARD/spruce/bin:$LD_LIBRARY_PATH
elif [ "$PLATFORM" = "Pixel2" ]; then
	export LD_LIBRARY_PATH=$(dirname "$0")/libs:/mnt/SDCARD/spruce/bin64:$LD_LIBRARY_PATH
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "reader" -c "./readerPixel2.gptk" &
else
	export LD_LIBRARY_PATH=$(dirname "$0")/libs:/mnt/SDCARD/spruce/bin64:$LD_LIBRARY_PATH
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "reader" -c "./reader.gptk" &
fi

cd $(dirname "$0")

export SCREEN_WIDTH=$DISPLAY_WIDTH
export SCREEN_HEIGHT=$DISPLAY_HEIGHT

sleep 0.6

if [ "$PLATFORM" = "A30" ]; then
	./reader32 2>log.txt
else
	./reader 2>log.txt
	kill -9 $(pidof gptokeyb)
fi
