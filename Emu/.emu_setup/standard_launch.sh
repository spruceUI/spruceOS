#!/bin/sh
# One Emu launch.sh to rule them all!
# Ry 2024-09-24

##### DEFINE BASE VARIABLES #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/Syncthing/syncthingFunctions.sh
log_message "-----Launching Emulator-----" -v
log_message "trying: $0 $@" -v
export EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
export GAME="$(basename "$1")"
export EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
export DEF_DIR="/mnt/SDCARD/Emu/.emu_setup/defaults"
export OPT_DIR="/mnt/SDCARD/Emu/.emu_setup/options"
export OVR_DIR="/mnt/SDCARD/Emu/.emu_setup/overrides"
export DEF_FILE="$DEF_DIR/${EMU_NAME}.opt"
export OPT_FILE="$OPT_DIR/${EMU_NAME}.opt"
export OVR_FILE="$OVR_DIR/$EMU_NAME/$GAME.opt"

##### IMPORT .OPT FILES #####

if [ -f "$DEF_FILE" ]; then
	. "$DEF_FILE"
else
	log_message "WARNING: Default .opt file not found for $EMU_NAME!" -v
fi

if [ -f "$OPT_FILE" ]; then
	. "$OPT_FILE"
else
	log_message "WARNING: System .opt file not found for $EMU_NAME!" -v
fi

if [ -f "$OVR_FILE" ]; then
	. "$OVR_FILE";
	log_message "Launch setting OVR_FILE detected @ $OVR_FILE" -v
else
	log_message "No launch OVR_FILE detected. Using current system settings." -v
fi

##### SET CPU MODE #####

case $EMU_NAME in
	"NDS")
		if [ "$MODE" = "overclock" ]; then
			{sleep 33 && set_overclock} &
		fi
		;;

	*)
		if [ "$MODE" = "overclock" ]; then
			set_overclock
		fi
		;;
esac

if [ "$MODE" != "overclock" ] && [ "$MODE" != "performance" ]; then
	/mnt/SDCARD/spruce/scripts/enforceSmartCPU.sh &
fi

wifi_needed=false
syncthing_enabled=false

##### RAC Check
if flag_check "save_active" && grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
	log_message "Retro Achievements enabled, WiFi connection needed"
	wifi_needed=true
fi

##### Syncthing Sync Check, perform only once per session #####
if flag_check "syncthing" && ! flag_check "syncthing_startup_synced"; then
	log_message "Syncthing is enabled, WiFi connection needed"
	wifi_needed=true
	syncthing_enabled=true
fi

if $syncthing_enabled; then
	if check_and_connect_wifi; then
		start_syncthing_process
		/mnt/SDCARD/spruce/bin/Syncthing/syncthing_sync_check.sh --startup
		flag_add "syncthing_startup_synced"
	else
		log_message "Failed to connect to WiFi, skipping Sync check"
	fi
elif $wifi_needed; then
	check_and_connect_wifi
fi

##### LAUNCH STUFF #####

case $EMU_NAME in
	"MEDIA")
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
		cd $EMU_DIR
		if [ -f 'libs/libEGL.so' ]; then
			rm -rf libs/libEGL.so
			rm -rf libs/libGLESv1_CM.so
			rm -rf libs/libGLESv2.so
		fi
		./drastic "$1"
		sync
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
		# pause global joystickinput 
		killall -STOP joystickinput

		# run new joystickinput that map joystick input to dpad input
		cd /mnt/SDCARD/.tmp_update/bin
		./joystickinput /dev/ttyS2 /config/joypad.config /dev/input/event3 -dpad &
        PID=$!

		export HOME="$EMU_DIR"
		export PATH="$HOME"/bin:$PATH
		export LD_LIBRARY_PATH="$HOME"/lib:$LD_LIBRARY_PATH
		export SDL_VIDEODRIVER=mali
		export SDL_JOYSTICKDRIVER=a30
		cd "$HOME"
		sed -i 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt"
		if [ "${GAME##*.}" = "splore" ]; then
			pico8_dyn -splore -width 640 -height 480 -root_path "/mnt/SDCARD/Roms/PICO8/"
		else
			pico8_dyn -width 640 -height 480 -scancodes -run "$1"
		fi
		sync

		# kill new joystickinput
		kill $PID

		# resume global joystickinput 
		killall -CONT joystickinput
		;;

	"PORTS")
		PORTS_DIR=/mnt/SDCARD/Roms/PORTS
		cd $PORTS_DIR
		/bin/sh "$1"
		;;

	"PSP")
		if [ "$CORE" = "standalone" ]; then
			cd $EMU_DIR
			export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR
			export HOME=/mnt/SDCARD
			
			./PPSSPPSDL "$*"
		else
			if flag_check "expertRA"; then
				export RA_BIN="retroarch"
			else
				export RA_BIN="ra32.miyoo"
			fi
			RA_DIR="/mnt/SDCARD/RetroArch"
			cd "$RA_DIR"
			HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"
		fi
		;;
	
	*)
		if flag_check "expertRA"; then
			export RA_BIN="retroarch"
		else
			export RA_BIN="ra32.miyoo"
		fi
		RA_DIR="/mnt/SDCARD/RetroArch"
		cd "$RA_DIR"

		HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"

		;;
		
esac

kill -9 $(pgrep enforceSmartCPU.sh)
log_message "-----Closing Emulator-----" -v
