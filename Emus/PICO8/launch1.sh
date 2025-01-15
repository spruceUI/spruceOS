#!/bin/sh

EMU_DIR="/mnt/SDCARD/Emu/PICO8"
GAMEDIR="/mnt/SDCARD/App/Pico8"

$EMU_DIR/cpufreq.sh
$EMU_DIR/cpuswitch1.sh

HOME="$GAMEDIR"

cd $HOME

LD_LIBRARY_PATH="$HOME/lib2:$LD_LIBRARY_PATH"
PATH="$HOME"/bin:$PATH


pico8_64 -run "$1" 2>&1 | tee $HOME/log.txt
