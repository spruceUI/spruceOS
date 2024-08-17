#!/bin/sh

echo 0 > /sys/devices/system/cpu/cpu3/online 
echo 0 > /sys/devices/system/cpu/cpu2/online 

/mnt/SDCARD/App/utils/utils performance 2 1512 384 1080 0

echo $0 $*
progdir=`dirname "$0"`
cd $progdir
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$progdir

echo "=============================================="
echo "==================== PPSSPP  ================="
echo "=============================================="

export HOME=/mnt/SDCARD
./miyoo282_xpad_inputd&
./PPSSPPSDL "$*"
killall miyoo282_xpad_inputd