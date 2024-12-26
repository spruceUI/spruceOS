#!/bin/sh
# One Emu launch.sh to rule them all!
# Ry 2024-09-24

##### DEFINE BASE VARIABLES #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# TODO: remove A30 check once Syncthing is implemented on Brick
if [ "$PLATFORM" = "A30" ]; then
	. /mnt/SDCARD/spruce/bin/Syncthing/syncthingFunctions.sh
fi

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


##### GENERAL FUNCTIONS #####

import_launch_options() {
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
}

set_cpu_mode() {
	if [ "$MODE" = "overclock" ]; then
		if [ "$EMU_NAME" = "NDS" ]; then
			( sleep 33 && set_overclock ) &
		else
			set_overclock
		fi
	fi

	if [ "$MODE" != "overclock" ] && [ "$MODE" != "performance" ]; then
		/mnt/SDCARD/spruce/scripts/enforceSmartCPU.sh &
	fi
}

handle_network_services() {

	wifi_needed=false
	syncthing_enabled=false
	wifi_connected=false

	##### RAC Check #####
	if ! setting_get "disableWifiInGame" && grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
		log_message "Retro Achievements enabled, WiFi connection needed"
		wifi_needed=true
	fi

	##### Syncthing Sync Check, perform only once per session #####
	if setting_get "syncthing" && ! flag_check "syncthing_startup_synced"; then
		log_message "Syncthing is enabled, WiFi connection needed"
		wifi_needed=true
		syncthing_enabled=true
	fi

	# Connect to WiFi if needed for any service
	if $wifi_needed; then
		if check_and_connect_wifi; then
			wifi_connected=true
		fi
	fi

	# Handle Syncthing sync if enabled
	if $syncthing_enabled && $wifi_connected; then
		start_syncthing_process
		/mnt/SDCARD/spruce/bin/Syncthing/syncthing_sync_check.sh --startup
		flag_add "syncthing_startup_synced"

	fi

	# Handle network service disabling
	if setting_get "disableNetworkServicesInGame" || setting_get "disableWifiInGame"; then
		/mnt/SDCARD/spruce/scripts/networkservices.sh off
		
		if setting_get "disableWifiInGame"; then
			if ifconfig wlan0 | grep "inet addr:" >/dev/null 2>&1; then
				ifconfig wlan0 down &
			fi
			killall wpa_supplicant
			killall udhcpc
		fi
	fi
}


##### EMULATOR LAUNCH FUNCTIONS #####

run_ffplay() {
	export HOME=$EMU_DIR
	export PATH=$EMU_DIR/bin:$PATH
	export LD_LIBRARY_PATH=$EMU_DIR/libs:/usr/miyoo/lib:/usr/lib:$LD_LIBRARY_PATH
	cd $EMU_DIR
	ffplay -vf transpose=2 -fs -i "$ROM_FILE"
}

run_drastic() {
	export HOME=$EMU_DIR
	cd $EMU_DIR

	if [ "$PLATFORM" = "A30" ]; then
		# the SDL library is hard coded to open ttyS0 for joystick raw input 
		# so we pause joystickinput and create soft link to serial port
		killall -q -STOP joystickinput
		ln -s /dev/ttyS2 /dev/ttyS0

		cd $EMU_DIR
		if [ ! -f "/tmp/.show_hotkeys" ]; then
			touch /tmp/.show_hotkeys
			LD_LIBRARY_PATH=libs2:/usr/miyoo/lib ./show_hotkeys
		fi
		
		export LD_LIBRARY_PATH=libs:/usr/miyoo/lib:/usr/lib
		export SDL_VIDEODRIVER=mmiyoo
		export SDL_AUDIODRIVER=mmiyoo
		export EGL_VIDEODRIVER=mmiyoo

		if [ -f 'libs/libEGL.so' ]; then
			rm -rf libs/libEGL.so
			rm -rf libs/libGLESv1_CM.so
			rm -rf libs/libGLESv2.so
		fi
		./drastic32 "$ROM_FILE"
		# remove soft link and resume joystickinput
		rm /dev/ttyS0
		killall -q -CONT joystickinput

	elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
		# export LD_PRELOAD=./lib64/libSDL2-2.0.so.0.2600.1
		export SDL_AUDIODRIVER=dsp
		./drastic64 "$ROM_FILE"
	fi
	sync
}

load_drastic_configs() {
	DS_DIR="/mnt/SDCARD/Emu/NDS/config"
	cp -f "$DS_DIR/drastic-$PLATFORM.cfg" "$DS_DIR/drastic.cfg"
}

save_drastic_configs() {
	DS_DIR="/mnt/SDCARD/Emu/NDS/config"
	cp -f "$DS_DIR/drastic.cfg" "$DS_DIR/drastic-$PLATFORM.cfg"
}

run_openbor() {
	export HOME=$EMU_DIR
	cd $HOME
	if [ "$PLATFORM" = "Brick" ]; then
		./OpenBOR_Brick
	else # assume A30
		export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib
		if [ "$GAME" == "Final Fight LNS.pak" ]; then
			./OpenBOR_mod "$ROM_FILE"
		else
			./OpenBOR_new "$ROM_FILE"
		fi
	fi
	sync
}

run_pico8() {
    # send signal USR2 to joystickinput to switch to KEYBOARD MODE
	# this allows joystick to be used as DPAD in MainUI
	killall -q -USR2 joystickinput

	export HOME="$EMU_DIR"
	export PATH="$HOME"/bin:$PATH:"/mnt/SDCARD/BIOS"

	if setting_get "pico8_stretch"; then
		SCALING="-draw_rect 0,0,480,640"
	else
		SCALING=""
	fi

	export SDL_VIDEODRIVER=mali
	export SDL_JOYSTICKDRIVER=a30
	cd "$HOME"
	sed -i 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt"
	if [ "${GAME##*.}" = "splore" ]; then
		pico8_dyn -splore -width 640 -height 480 -root_path "/mnt/SDCARD/Roms/PICO8/" $SCALING
	else
		pico8_dyn -width 640 -height 480 -scancodes -run "$ROM_FILE" $SCALING
	fi
	sync

	# send signal USR1 to joystickinput to switch to ANALOG MODE
	killall -q -USR1 joystickinput
}

load_pico8_control_profile() {
	HOME="$EMU_DIR"
	P8_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"
	CONTROL_PROFILE="$(setting_get "pico8_control_profile")"

	if [ "$CONTROL_PROFILE" = "Steward" ]; then
		export LD_LIBRARY_PATH="$HOME"/lib-stew:$LD_LIBRARY_PATH
	else
		export LD_LIBRARY_PATH="$HOME"/lib-cine:$LD_LIBRARY_PATH
	fi

	case "$CONTROL_PROFILE" in
		"Doubled") 
			cp -f "$P8_DIR/sdl_controllers.facebuttons" "$P8_DIR/sdl_controllers.txt"
			;;
		"One-handed")
			cp -f "$P8_DIR/sdl_controllers.onehand" "$P8_DIR/sdl_controllers.txt"
			;;
		"Racing")
			cp -f "$P8_DIR/sdl_controllers.racing" "$P8_DIR/sdl_controllers.txt"
			;;
		"Doubled 2") 
			cp -f "$P8_DIR/sdl_controllers.facebuttons_reverse" "$P8_DIR/sdl_controllers.txt"
			;;
		"One-handed 2")
			cp -f "$P8_DIR/sdl_controllers.onehand_reverse" "$P8_DIR/sdl_controllers.txt"
			;;
		"Racing 2")
			cp -f "$P8_DIR/sdl_controllers.racing_reverse" "$P8_DIR/sdl_controllers.txt"
			;;
	esac
}

run_port() {
	PORTS_DIR=/mnt/SDCARD/Roms/PORTS
	cd $PORTS_DIR
	/bin/sh "$ROM_FILE"
}

move_dotconfig_into_place() {
	if [ -d "/mnt/SDCARD/Emu/.emu_setup/.config" ]; then
		cp -rf "/mnt/SDCARD/Emu/.emu_setup/.config" "/mnt/SDCARD/.config" && log_message "Copied .config folder to root of SD card."
	else
		log_message "WARNING!!! No .config folder found!"
	fi
}

run_ppsspp() {
	export HOME=/mnt/SDCARD
	cd $EMU_DIR
	if [ "$PLATFORM" = "A30" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR
		./PPSSPPSDL "$ROM_FILE"
	elif [ "$PLATFORM" = "Brick" ]; then 	
		export SDL_GAMECONTROLLERCONFIG_FILE=/mnt/SDCARD/Emus/PPSSPP/assets/gamecontrollerdb.txt
		./PPSSPPSDL_Brick "$ROM_FILE"
	fi
}

load_ppsspp_configs() {
	PSP_DIR="/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM"
	cp -f "$PSP_DIR/controls-$PLATFORM.ini" "$PSP_DIR/controls.ini"
	cp -f "$PSP_DIR/ppsspp-$PLATFORM.ini" "$PSP_DIR/ppsspp.ini"
}

save_ppsspp_configs() {
	PSP_DIR="/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM"
	cp -f "$PSP_DIR/controls.ini" "$PSP_DIR/controls-$PLATFORM.ini"
	cp -f "$PSP_DIR/ppsspp.ini" "$PSP_DIR/ppsspp-$PLATFORM.ini"
}

run_retroarch() {
	if [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
		export RA_BIN="ra64.trimui"
	elif setting_get "expertRA" || [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
		export RA_BIN="retroarch"
	else
		export RA_BIN="ra32.miyoo"
	fi
	RA_DIR="/mnt/SDCARD/RetroArch"
	cd "$RA_DIR"

	if [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
		CORE_DIR="$RA_DIR/.retroarch/cores-a133"
	else
		CORE_DIR="$RA_DIR/.retroarch/cores"
	fi
	HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$CORE_DIR/${CORE}_libretro.so" "$ROM_FILE"
}

ready_architecture_dependent_states() {
	STATES="/mnt/SDCARD/Saves/states"
	if [ "$PLATFORM" = "A30" ]; then 
		[ -d "$STATES/RACE-32" ] && mv "$STATES/RACE-32" "$STATES/RACE"
		[ -d "$STATES/fake-08-32" ] && mv "$STATES/fake-08-32" "$STATES/fake-08"
		[ -d "$STATES/PCSX-ReARMed-32" ] && mv "$STATES/PCSX-ReARMed-32" "$STATES/PCSX-ReARMed"
		[ -d "$STATES/ChimeraSNES-32" ] && mv "$STATES/ChimeraSNES-32" "$STATES/ChimeraSNES"

	elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "Flip" ];  then
		[ -d "$STATES/RACE-64" ] && mv "$STATES/RACE-64" "$STATES/RACE"
		[ -d "$STATES/fake-08-64" ] && mv "$STATES/fake-08-64" "$STATES/fake-08"
		[ -d "$STATES/PCSX-ReARMed-64" ] && mv "$STATES/PCSX-ReARMed-64" "$STATES/PCSX-ReARMed"
		[ -d "$STATES/ChimeraSNES-64" ] && mv "$STATES/ChimeraSNES-64" "$STATES/ChimeraSNES"
	fi
}

stash_architecture_dependent_states() {
	STATES="/mnt/SDCARD/Saves/states"
	if [ "$PLATFORM" = "A30" ]; then 
		[ -d "$STATES/RACE" ] && mv "$STATES/RACE" "$STATES/RACE-32"
		[ -d "$STATES/fake-08" ] && mv "$STATES/fake-08" "$STATES/fake-08-32"
		[ -d "$STATES/PCSX-ReARMed"] && mv "$STATES/PCSX-ReARMed" "$STATES/PCSX-ReARMed-32"
		[ -d "$STATES/ChimeraSNES" ] && mv "$STATES/ChimeraSNES" "$STATES/ChimeraSNES-32"

	elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "Flip" ];  then
		[ -d "$STATES/RACE" ] && mv "$STATES/RACE" "$STATES/RACE-64"
		[ -d "$STATES/fake-08" ] && mv "$STATES/fake-08" "$STATES/fake-08-64"
		[ -d "$STATES/PCSX-ReARMed"] && mv "$STATES/PCSX-ReARMed" "$STATES/PCSX-ReARMed-64"
		[ -d "$STATES/ChimeraSNES" ] && mv "$STATES/ChimeraSNES" "$STATES/ChimeraSNES-64"

	fi
}

load_n64_controller_profile() {
	PROFILE="$(setting_get "n64_control_profile")"
	SRC="/mnt/SDCARD/Emu/.emu_setup/n64_controller"
	DST="/mnt/SDCARD/RetroArch/.retroarch/config/remaps"
	LUDI="LudicrousN64 Xtreme Amped"
	PARA="ParaLLEl N64"
	MUPEN="Mupen64Plus GLES2"
	cp -f "${SRC}/${PROFILE}.rmp" "${DST}/${LUDI}/${LUDI}.rmp"
	cp -f "${SRC}/${PROFILE}.rmp" "${DST}/${PARA}/${PARA}.rmp"
	cp -f "${SRC}/${PROFILE}.rmp" "${DST}/${MUPEN}/${MUPEN}.rmp"
}

save_custom_n64_controller_profile() {
	PROFILE="$(setting_get "n64_control_profile")"
	if [ "$PROFILE" = "Custom" ]; then
		SRC="/mnt/SDCARD/Emu/.emu_setup/n64_controller"
		DST="/mnt/SDCARD/RetroArch/.retroarch/config/remaps"
		LUDI="LudicrousN64 Xtreme Amped"
		PARA="ParaLLEl N64"
		MUPEN="Mupen64Plus GLES2"
		if [ "$CORE" = "km_ludicrousn64_2k22_xtreme_amped" ]; then
			cp -f "${DST}/${LUDI}/${LUDI}.rmp" "${SRC}/Custom.rmp"
		elif [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
			cp -f "${DST}/${PARA}/${PARA}.rmp" "${SRC}/Custom.rmp"
		else # CORE is mupen64plus
			cp -f "${DST}/${MUPEN}/${MUPEN}.rmp" "${SRC}/Custom.rmp"
		fi
	fi
}

##### MAIN EXECUTION #####

import_launch_options

set_cpu_mode

# TODO: remove A30 check once network services implemented on Brick
[ "$PLATFORM" = "A30" ] && handle_network_services

flag_add 'emulator_launched'

# Pause simple mode watchdog so in-game Konami code doesn't break it
kill -19 $(pgrep -f simple_mode_watchdog.sh) 2>/dev/null

# Sanitize the rom path
export ROM_FILE="$(readlink -f "$1")"

case $EMU_NAME in
	"MEDIA")
		if [ "$PLATFORM" = "A30" ]; then
			run_ffplay
		elif [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
			export CORE="ffmpeg"
			run_retroarch
		fi
		;;
	"NDS")
		load_drastic_configs
		run_drastic
		save_drastic_configs
		;;
	"OPENBOR")
		run_openbor
		;;
	"PICO8")
		load_pico8_control_profile
		run_pico8
		;;
	"PORTS")
		run_port
		;;
	"PSP")
		if [ "$CORE" = "standalone" ]; then
			[ ! -d "/mnt/SDCARD/.config" ] && move_dotconfig_into_place
			load_ppsspp_configs
			run_ppsspp
			save_ppsspp_configs
		else
			run_retroarch
		fi
		;;
	*)
		[ $EMU_NAME = "N64" ] && load_n64_controller_profile
		ready_architecture_dependent_states
		run_retroarch
		stash_architecture_dependent_states
		[ $EMU_NAME = "N64" ] && save_custom_n64_controller_profile
		;;
esac

kill -18 $(pgrep -f simple_mode_watchdog.sh) 2>/dev/null # unpause
kill -9 $(pgrep -f enforceSmartCPU.sh)
log_message "-----Closing Emulator-----" -v

auto_regen_tmp_update
