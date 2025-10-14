#!/bin/sh
<<<<<<< HEAD:App/KoReader/launch.sh
progdir=`dirname "$0"`
GAMEDIR="$progdir"
cd $GAMEDIR
#export SDL_GAMECONTROLLERCONFIG_FILE="../PortMaster/gamecontrollerdb.txt"
export SDL_GAMECONTROLLERCONFIG="030000005e0400008e02000014010000,X360 Controller,a:b1,b:b0,back:b6,guide:b8,leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b10,righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b3,y:b2,platform:Linux,"
#./gptokeyb "reader" -c "./reader.gptk" &
LD_LIBRARY_PATH="libs:/usr/lib32/:$LD_LIBRARY_PATH" ./luajit reader.lua
#kill -9 $(pidof gptokeyb)

#cd /$directory/ports/jy
#sudo ./jysdllua.run
=======

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
>>>>>>> parent of 5d60315d (koreader):App/PixelReader/launch.sh
