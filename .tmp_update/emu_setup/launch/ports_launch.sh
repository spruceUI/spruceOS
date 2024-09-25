#!/bin/sh
echo $0 $*

export PORTS_DIR=/mnt/SDCARD/Roms/PORTS
export EMU_DIR="$(dirname "$0")"
export EMU_NAME="$(basename "$EMU_DIR")"
export DEF_DIR="/mnt/SDCARD/.tmp_update/emu_setup/defaults"
export GAME="$(basename "$1")"
export OVR_DIR="$EMU_DIR/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"

. "$DEF_DIR/${EMU_NAME}.opt"
. "$EMU_DIR/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

if [ "$GOV" = "overclock" ]; then
	/mnt/SDCARD/App/utils/utils "performance" 4 1512 384 1080 1
elif [ "$GOV" = "performance" ]; then
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

cd $PORTS_DIR
/bin/sh "$1"
