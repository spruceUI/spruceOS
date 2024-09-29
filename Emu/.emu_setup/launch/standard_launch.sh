#!/bin/sh

. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh
log_message "-----Launching Emulator-----"
log_message "trying: $0 $@"
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
	log_message "Launch setting override detected @ $OVERRIDE"
else
	log_message "No launch override detected. Using current system settings."
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
	log_message "CPU Mode set to SMART"
}

set_performance() {
	/mnt/SDCARD/App/utils/utils "performance" 4 1344 384 1080 1	
	log_message "CPU Mode set to PERFORMANCE"

}

set_overclock() {
	/mnt/SDCARD/App/utils/utils "performance" 4 1512 384 1080 1
	log_message "CPU Mode set to OVERCLOCK"

}

enforce_smart() {
	while true; do
		sleep 10
		governor="$(cat "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")"
		if [ $governor != "conservative" ]; then
			log_message "CPU Mode has changed. Re-enforcing SMART mode"
			set_smart
		fi
	done
}

if [ "$MODE" = "overclock" ]; then
	set_overclock
elif [ "$MODE" = "performance" ]; then
	set_performance
else
	set_smart
	enforce_smart &
	ENFORCE_PID="$!"
fi

RA_DIR="/mnt/SDCARD/RetroArch"
cd "$RA_DIR"
HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"

kill -9 "$ENFORCE_PID"
log_message "-----Closing Emulator-----"