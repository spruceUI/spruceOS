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

export HOME="/mnt/SDCARD/App/PICO"
export PATH="$HOME"/bin:$PATH
export LD_LIBRARY_PATH="$HOME"/lib:$LD_LIBRARY_PATH
export SDL_VIDEODRIVER=mali
export SDL_JOYSTICKDRIVER=a30

cd "$HOME"

sed -i 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt"

if [ "$MODE" = "overclock" ]; then
	/mnt/SDCARD/App/utils/utils "performance" 4 1512 384 1080 1
elif [ "$MODE" = "performance" ]; then
		/mnt/SDCARD/App/utils/utils "performance" 4 1344 384 1080 1
else
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
fi

pico8_dyn -width 640 -height 480 -scancodes -run "$1"
sync
