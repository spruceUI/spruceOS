#!/bin/sh
mydir=`dirname "$0"`

export HOME=$mydir
export PATH=$mydir/bin:$PATH
export LD_LIBRARY_PATH=$mydir/libs:/usr/miyoo/lib:/usr/lib:$LD_LIBRARY_PATH

export GAME="$(basename "$1")"
export OVR_DIR="$mydir/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"

. "$mydir/default.opt"
. "$mydir/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

echo 1 > /sys/devices/system/cpu/cpu2/online
echo 1 > /sys/devices/system/cpu/cpu3/online
echo conservative > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo 30 > /sys/devices/system/cpu/cpufreq/conservative/down_threshold
echo 312000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

cd $mydir
ffplay -vf transpose=2 -fs -i "$1"
