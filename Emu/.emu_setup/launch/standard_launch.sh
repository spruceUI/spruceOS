#!/bin/sh

export RA_DIR="/mnt/SDCARD/RetroArch"
export EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
export EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
export DEF_DIR="/mnt/SDCARD/Emu/.emu_setup/defaults"
export GAME="$(basename "$1")"
export OVR_DIR="$EMU_DIR/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"

. "$DEF_DIR/${EMU_NAME}.opt"
. "$EMU_DIR/system.opt"
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

enforce_smart() {
	while true; do
		sleep 10
		governor="$(cat "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")"
		if [ $governor != "conservative" ]; then
			set_smart
		fi
	done
}

if [ "$MODE" = "overclock" ]; then
	/mnt/SDCARD/App/utils/utils "performance" 4 1512 384 1080 1
elif [ "$MODE" = "performance" ]; then
	/mnt/SDCARD/App/utils/utils "performance" 4 1344 384 1080 1
else
	set_smart
	enforce_smart &
	ENFORCE_PID="$!"
fi

echo $0 $*

cd "$RA_DIR"
HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"

kill -9 "$ENFORCE_PID"