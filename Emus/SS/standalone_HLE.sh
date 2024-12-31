#!/bin/sh
echo $0 $*
EMU_DIR=/mnt/SDCARD/Emu/SS

$EMU_DIR/cpuswitch.sh
$EMU_DIR/performance.sh

cd $EMU_DIR
export LD_LIBRARY_PATH=$EMU_DIR/lib:$LD_LIBRARY_PATH
export HOME="$EMU_DIR"

./gptokeyb -k "yabasanshiro" -c "keys.gptk" &
./yabasanshiro -r 3 -i "$@"
$ESUDO kill -9 $(pidof gptokeyb)
