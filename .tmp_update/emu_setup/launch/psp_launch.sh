#!/bin/sh

export EMU_DIR="$(dirname "$0")"
export GAME="$(basename "$1")"
export OVR_DIR="$EMU_DIR/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"

. "$EMU_DIR/default.opt"
. "$EMU_DIR/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

echo 1 > /sys/devices/system/cpu/cpu2/online
echo 1 > /sys/devices/system/cpu/cpu3/online
echo conservative > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo 30 > /sys/devices/system/cpu/cpufreq/conservative/down_threshold
echo 70 > /sys/devices/system/cpu/cpufreq/conservative/up_threshold
echo 3 > /sys/devices/system/cpu/cpufreq/conservative/freq_step
echo 1 > /sys/devices/system/cpu/cpufreq/conservative/sampling_down_factor
echo 240000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

echo $0 $*
cd $EMU_DIR
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR

echo "=============================================="
echo "==================== PPSSPP  ================="
echo "=============================================="

export HOME=/mnt/SDCARD
./miyoo282_xpad_inputd&
./PPSSPPSDL "$*"
killall miyoo282_xpad_inputd
