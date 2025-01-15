#!/bin/sh
cd $(dirname "$0")



SDL_GAMECONTROLLERCONFIG_FILE="./gamecontrollerdb.txt" ./gptokeyb -k "mpv" -c "./mpv.gptk" &
sleep 1
MPV_HOME=./ LD_LIBRARY_PATH="$LD_LIBRARY_PATH:lib" ./mpv "$*"
kill -9 $(pidof gptokeyb)
