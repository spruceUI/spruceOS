#!/bin/sh
cd $(dirname "$0")



SDL_GAMECONTROLLERCONFIG_FILE="./gamecontrollerdb.txt" ./gptokeyb -k "ffplay" -c "./ffplay.gptk" &
sleep 1
LD_LIBRARY_PATH="$LD_LIBRARY_PATH:lib" ./ffplay -x 640 -y 480 "$*"
kill -9 $(pidof gptokeyb)
