#!/bin/sh

EMU_DIR="/mnt/SDCARD/Emu/PICO8"
GAMEDIR="/mnt/SDCARD/App/Pico8"

$EMU_DIR/cpufreq.sh
$EMU_DIR/cpuswitch1.sh

HOME="$GAMEDIR"

cd $HOME

LD_LIBRARY_PATH="$HOME/lib2:$LD_LIBRARY_PATH"
PATH="$HOME"/bin:$PATH

resolution=$(fbset | grep 'geometry' | awk '{print $2,$3}')
width=$(echo $resolution | awk '{print $1}')
height=$(echo $resolution | awk '{print $2}')

draw_rect="-draw_rect 0,0,${width},${height}"

pico8_64 $draw_rect -run "$1" 2>&1 | tee $HOME/log.txt
