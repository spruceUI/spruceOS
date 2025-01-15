#!/bin/sh
echo $0 $*

RA_DIR=/mnt/SDCARD/RetroArch
EMU_DIR=/mnt/SDCARD/Emu/SS

$EMU_DIR/cpuswitch.sh
$EMU_DIR/performance.sh

cd $RA_DIR/

#disable netplay
NET_PARAM=

HOME=$RA_DIR/ $RA_DIR/ra64.miyoo -v $NET_PARAM -L $RA_DIR/.retroarch/cores/yabasanshiro_libretro.so "$@"
