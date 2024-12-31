#!/bin/sh
#echo "===================================="
echo ============cmd:$EMU_DIR/easyrpg_libretro.so $*
progdir=`dirname "$0"`
RA_DIR=$progdir/../../RetroArch
ROM_DIR=/mnt/SDCARD/Roms/EASYRPG
EMU_DIR=$progdir
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$progdir #:$RA_DIR/.retroarch.kai/lib



cd $RA_DIR/

#HOME=$RA_DIR/ $RA_DIR/ra64.miyoo -v $NET_PARAM -L $EMU_DIR/easyrpg_libretro.so "$*"
#HOME=$RA_DIR/ $RA_DIR/ra64.miyoo -v $NET_PARAM -L $RA_DIR/.retroarch/cores/easyrpg_libretro.so "$*"
ROMNAME="$1"
BASEROMNAME=${ROMNAME##*/}
ROMNAMETMP=${BASEROMNAME%.*}
if [ -f "${ROM_DIR}/${ROMNAMETMP}/RPG_RT.ldb" ]; then
HOME=$RA_DIR/ $RA_DIR/ra64.miyoo -v $NET_PARAM -L $RA_DIR/.retroarch/cores/easyrpg_libretro.so "${ROM_DIR}/${ROMNAMETMP}/RPG_RT.ldb"
else
HOME=$RA_DIR/ $RA_DIR/ra64.miyoo -v $NET_PARAM -L $RA_DIR/.retroarch/cores/easyrpg_libretro.so "$*"
fi
