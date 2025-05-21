#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
	export LD_LIBRARY_PATH=$(dirname "$0")/libs32:/mnt/SDCARD/spruce/bin:$LD_LIBRARY_PATH
else
	export LD_LIBRARY_PATH=$(dirname "$0")/libs:/mnt/SDCARD/spruce/bin64:$LD_LIBRARY_PATH
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "reader" -c "./reader.gptk" &
fi

cd $(dirname "$0")

RESOLUTION=$("/mnt/SDCARD/App/PortMaster/.portmaster/PortMaster/sdl_resolution.aarch64" 2>/dev/null | grep -a 'Current' | awk -F ': ' '{print $2}')
DISPLAY_WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f 1)
DISPLAY_HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f 2)
export SCREEN_WIDTH=$DISPLAY_WIDTH
export SCREEN_HEIGHT=$DISPLAY_HEIGHT

sleep 0.6

if [ "$PLATFORM" = "A30" ]; then
	./reader32 2>log.txt
else
	./reader
	
	kill -9 $(pidof gptokeyb)
fi