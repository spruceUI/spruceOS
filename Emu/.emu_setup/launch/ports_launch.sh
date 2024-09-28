#!/bin/sh

export EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
export EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
export DEF_DIR="/mnt/SDCARD/Emu/.emu_setup/defaults"
export OPT_DIR="/mnt/SDCARD/Emu/.emu_setup/options"
export OVR_DIR="/mnt/SDCARD/Emu/.emu_setup/overrides"
export GAME="$(basename "$1")"
export OVERRIDE="$OVR_DIR/$EMU_NAME/$GAME.opt"

. "$DEF_DIR/${EMU_NAME}.opt"
. "$OPT_DIR/${EMU_NAME}.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

set_smart() {
	echo 1 > /sys/devices/system/cpu/cpu2/online
	echo 1 > /sys/devices/system/cpu/cpu3/online
	echo conservative > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	echo 30 > /sys/devices/system/cpu/cpufreq/conservative/down_threshold
	echo 70 > /sys/devices/system/cpu/cpufreq/conservative/up_threshold
	echo 3 > /sys/devices/system/cpu/cpufreq/conservative/freq_step
	echo 1 > /sys/devices/system/cpu/cpufreq/conservative/sampling_down_factor
	echo 400000 > /sys/devices/system/cpu/cpufreq/conservative/sampling_rate
	echo 200000 > /sys/devices/system/cpu/cpufreq/conservative/sampling_rate_min
	echo "$scaling_min_freq" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
}

set_performance() {
	/mnt/SDCARD/App/utils/utils "performance" 4 1344 384 1080 1	
}

set_overclock() {
	/mnt/SDCARD/App/utils/utils "performance" 4 1512 384 1080 1
}

if [ "$MODE" = "overclock" ]; then
	set_overclock
elif [ "$MODE" = "performance" ]; then
	set_performance
else
	set_smart
fi

PORTS_DIR=/mnt/SDCARD/Roms/PORTS
cd $PORTS_DIR
/bin/sh "$1"
