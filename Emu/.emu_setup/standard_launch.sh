#!/bin/sh
# One Emu launch.sh to rule them all!
# Ry 2024-09-24

##### DEFINE BASE VARIABLES #####

. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh
log_message "-----Launching Emulator-----"
log_message "trying: $0 $@"
export EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
export GAME="$(basename "$1")"
export EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
export DEF_DIR="/mnt/SDCARD/Emu/.emu_setup/defaults"
export OPT_DIR="/mnt/SDCARD/Emu/.emu_setup/options"
export OVR_DIR="/mnt/SDCARD/Emu/.emu_setup/OVR_FILEs"
export DEF_FILE="$DEF_DIR/${EMU_NAME}.opt"
export OPT_FILE="$OPT_DIR/${EMU_NAME}.opt"
export OVR_FILE="$OVR_DIR/$EMU_NAME/$GAME.opt"

##### IMPORT .OPT FILES #####

if [ -f "$DEF_FILE" ]; then
	. "$DEF_FILE"
else
	log_message "WARNING: Default .opt file not found for $EMU_NAME!"
fi

if [ -f "$OPT_FILE" ]; then
	. "$OPT_FILE"
else
	log_message "WARNING: System .opt file not found for $EMU_NAME!"
fi

if [ -f "$OVR_FILE" ]; then
	. "$OVR_FILE";
	log_message "Launch setting OVR_FILE detected @ $OVR_FILE"
else
	log_message "No launch OVR_FILE detected. Using current system settings."
fi

##### DEFINE FUNCTIONS #####

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

##### SET CPU MODE #####

case $EMU_NAME in
	"NDS")
		if [ "$MODE" = "overclock" ]; then
			{sleep 12 && set_overclock} &
		elif [ "$MODE" = "performance" ]; then
			{sleep 12 && set_performance} &
		else
			{sleep 12 && set_smart} &
		fi
		;;

	"FFPLAY"|"OPENBOR"|"PICO8"|"PORTS"|"PSP")
		if [ "$MODE" = "overclock" ]; then
			set_overclock
		elif [ "$MODE" = "performance" ]; then
			set_performance
		else
			set_smart
		fi
		;;

	*)
		if [ "$MODE" = "overclock" ]; then
			set_overclock
		elif [ "$MODE" = "performance" ]; then
			set_performance
		else
			set_smart
			enforce_smart &
			ENFORCE_PID="$!"
		fi
		;;
esac

##### LAUNCH STUFF #####

case $EMU_NAME in
	"FFPLAY")
		export HOME=$EMU_DIR
		export PATH=$EMU_DIR/bin:$PATH
		export LD_LIBRARY_PATH=$EMU_DIR/libs:/usr/miyoo/lib:/usr/lib:$LD_LIBRARY_PATH
		cd $EMU_DIR
		ffplay -vf transpose=2 -fs -i "$1"
		;;

	"NDS")
		cd $EMU_DIR
		if [ ! -f "/tmp/.show_hotkeys" ]; then
			touch /tmp/.show_hotkeys
			LD_LIBRARY_PATH=libs2:/usr/miyoo/lib ./show_hotkeys
		fi
		export HOME=$EMU_DIR
		export LD_LIBRARY_PATH=libs:/usr/miyoo/lib:/usr/lib
		export SDL_VIDEODRIVER=mmiyoo
		export SDL_AUDIODRIVER=mmiyoo
		export EGL_VIDEODRIVER=mmiyoo
		sv=`cat /proc/sys/vm/swappiness`
		echo 10 > /proc/sys/vm/swappiness
		cd $EMU_DIR
		if [ -f 'libs/libEGL.so' ]; then
			rm -rf libs/libEGL.so
			rm -rf libs/libGLESv1_CM.so
			rm -rf libs/libGLESv2.so
		fi
		./drastic "$1"
		sync
		echo $sv > /proc/sys/vm/swappiness
		;;

	"OPENBOR")
		export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib
		export HOME=$EMU_DIR
		cd $HOME
		if [ "$GAME" == "Final Fight LNS.pak" ]; then
			./OpenBOR_mod "$1"
		else
			./OpenBOR_new "$1"
		fi
		sync
		;;
	
	"PICO8")
		export HOME="/mnt/SDCARD/App/PICO"
		export PATH="$HOME"/bin:$PATH
		export LD_LIBRARY_PATH="$HOME"/lib:$LD_LIBRARY_PATH
		export SDL_VIDEODRIVER=mali
		export SDL_JOYSTICKDRIVER=a30
		cd "$HOME"
		sed -i 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt"
		pico8_dyn -width 640 -height 480 -scancodes -run "$1"
		sync
		;;

	"PORTS")
		PORTS_DIR=/mnt/SDCARD/Roms/PORTS
		cd $PORTS_DIR
		/bin/sh "$1"
		;;

	"PSP")
		cd $EMU_DIR
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR
		export HOME=/mnt/SDCARD
		./miyoo282_xpad_inputd&
		./PPSSPPSDL "$*"
		killall miyoo282_xpad_inputd
		;;
	
	*)
		RA_DIR="/mnt/SDCARD/RetroArch"
		cd "$RA_DIR"
		HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"
		kill -9 "$ENFORCE_PID"
		;;

esac

log_message "-----Closing Emulator-----"