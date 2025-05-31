#!/bin/sh
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
