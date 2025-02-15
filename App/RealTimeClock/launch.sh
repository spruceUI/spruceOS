#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
	./rtc
elif [ "$PLATFORM" = "Flip" ]; then
	/mnt/SDCARD/spruce/bin64/gptokeyb -k "rtc" -c "./rtc.gptk" &
	sleep 1
	./rtc-Flip
	kill -9 $(pidof gptokeyb)
fi
auto_regen_tmp_update
