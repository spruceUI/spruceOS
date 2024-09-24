#!/bin/sh

export HOME=`dirname "$0"`
export mypak=`basename "$1"`
export OVR_DIR="$HOME/overrides"
export OVERRIDE="$OVR_DIR/$mypak.opt"

. "$HOME/default.opt"
. "$HOME/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

echo 1 > /sys/devices/system/cpu/cpu2/online
echo 1 > /sys/devices/system/cpu/cpu3/online
echo conservative > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo 30 > /sys/devices/system/cpu/cpufreq/conservative/down_threshold
echo 312000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib

cd $HOME
if [ "$mypak" == "Final Fight LNS.pak" ]; then
    ./OpenBOR_mod "$1"
else
    ./OpenBOR_new "$1"
fi
sync
