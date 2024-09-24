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

if [ "$GOV" -eq "overclock" ]; then
	/mnt/SDCARD/App/utils/utils "performance" 4 1512 384 1080 1
elif [ "$GOV" - eq "performance" ]; then
		/mnt/SDCARD/App/utils/utils "performance" 4 1344 384 1080 1
else
	echo 1 > /sys/devices/system/cpu/cpu2/online
	echo 1 > /sys/devices/system/cpu/cpu3/online
	echo conservative > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	echo "$down_threshold" > /sys/devices/system/cpu/cpufreq/conservative/down_threshold
	echo "$up_threshold" > /sys/devices/system/cpu/cpufreq/conservative/up_threshold
	echo "$freq_step" > /sys/devices/system/cpu/cpufreq/conservative/freq_step
	echo "$sampling_down_factor" > /sys/devices/system/cpu/cpufreq/conservative/sampling_down_factor
	echo "$sampling_rate" > /sys/devices/system/cpu/cpufreq/conservative/sampling_rate
	echo "$sampling_rate_min" > /sys/devices/system/cpu/cpufreq/conservative/sampling_rate_min
	echo "$scaling_min_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
fi

export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib

cd $HOME
if [ "$mypak" == "Final Fight LNS.pak" ]; then
    ./OpenBOR_mod "$1"
else
    ./OpenBOR_new "$1"
fi
sync
