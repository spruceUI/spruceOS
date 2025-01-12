#!/bin/sh
echo $0 $*
progdir=`dirname "$0"`
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$progdir

RA_DIR=$progdir/../../RetroArch
EMU_DIR=$progdir


$EMU_DIR/cpufreq.sh


cd $RA_DIR/

#disable netplay
NET_PARAM=

HOME=$RA_DIR/ $RA_DIR/ra64.miyoo -v $NET_PARAM -L $RA_DIR/.retroarch/cores/retro8_libretro.so "$*"
