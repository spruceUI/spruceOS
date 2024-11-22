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

if [ "$MODE" = "overclock" ]; then
	if [ "$EMU_NAME" = "NDS" ]; then
		{sleep 33 && set_overclock} &
	else
		set_overclock
	fi
fi

if [ "$MODE" != "overclock" ] && [ "$MODE" != "performance" ]; then
	/mnt/SDCARD/spruce/scripts/enforceSmartCPU.sh &
fi

wifi_needed=false
syncthing_enabled=false
wifi_connected=false

##### RAC Check
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
    /mnt/SDCARD/spruce/scripts/networkservices.sh off &
    
    if setting_get "disableWifiInGame"; then
        if ifconfig wlan0 | grep "inet addr:" >/dev/null 2>&1; then
            ifconfig wlan0 down &
        fi
        killall wpa_supplicant
        killall udhcpc
    fi
fi

flag_add 'emulator_launched'

##### LAUNCH STUFF #####

# we sanitise the rom path
ROM_FILE="$(readlink -f "$1")"

case $EMU_NAME in
	"MEDIA")
		export HOME=$EMU_DIR
		export PATH=$EMU_DIR/bin:$PATH
		export LD_LIBRARY_PATH=$EMU_DIR/libs:/usr/miyoo/lib:/usr/lib:$LD_LIBRARY_PATH
		cd $EMU_DIR
		ffplay -vf transpose=2 -fs -i "$ROM_FILE"
		;;

	"NDS")
		# the SDL library is hard coded to open ttyS0 for joystick raw input 
		# so we pause joystickinput and create soft link to serial port
		killall -STOP joystickinput
        ln -s /dev/ttyS2 /dev/ttyS0

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
		./drastic "$ROM_FILE"
		sync

        # remove soft link and resume joystickinput
        rm /dev/ttyS0
		killall -CONT joystickinput

		;;

	"OPENBOR")
		export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib
		export HOME=$EMU_DIR
		cd $HOME
		if [ "$GAME" == "Final Fight LNS.pak" ]; then
			./OpenBOR_mod "$ROM_FILE"
		else
			./OpenBOR_new "$ROM_FILE"
		fi
		sync
		;;
	
	"PICO8")
        # send signal USR2 to joystickinput to switch to KEYBOARD MODE
        # this allows joystick to be used as DPAD in MainUI
        killall -USR2 joystickinput

		export HOME="$EMU_DIR"
		export PATH="$HOME"/bin:$PATH

		P8_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"
		CONTROL_PROFILE="$(setting_get "pico8_control_profile")"

		if [ "$CONTROL_PROFILE" = "Steward" ]; then
			export LD_LIBRARY_PATH="$HOME"/lib-stew:$LD_LIBRARY_PATH
		else
			export LD_LIBRARY_PATH="$HOME"/lib-cine:$LD_LIBRARY_PATH
		fi

		if [ "$CONTROL_PROFILE" = "Doubled" ]; then
			cp -f "$P8_DIR/sdl_controllers.facebuttons" "$P8_DIR/sdl_controllers.txt"
		elif [ "$CONTROL_PROFILE" = "One-handed" ]; then
			cp -f "$P8_DIR/sdl_controllers.onehand" "$P8_DIR/sdl_controllers.txt"
		elif [ "$CONTROL_PROFILE" = "Racing" ]; then
			cp -f "$P8_DIR/sdl_controllers.racing" "$P8_DIR/sdl_controllers.txt"
		fi

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
        killall -USR1 joystickinput

		;;

	"PORTS")
		PORTS_DIR=/mnt/SDCARD/Roms/PORTS
		cd $PORTS_DIR
		/bin/sh "$ROM_FILE"
		;;

	"PSP")
		if [ "$CORE" = "standalone" ]; then

			# move .config folder into place in case emu setup never ran
			if [ ! -d "/mnt/SDCARD/.config" ]; then
				if [ -d "$SETUP_DIR/.config" ]; then
					cp -rf "$SETUP_DIR/.config" "/mnt/SDCARD/.config" && log_message "emu_setup.sh: copied .config folder to root of SD card."
				else
					log_message "emu_setup.sh: WARNING!!! No .config folder found!"
				fi
			else
				log_message "emu_setup.sh: .config folder already in place at SD card root."
			fi

			cd $EMU_DIR
			export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR
			export HOME=/mnt/SDCARD
			
			./PPSSPPSDL "$ROM_FILE"
		else
			if setting_get "expertRA"; then
				export RA_BIN="retroarch"
			else
				export RA_BIN="ra32.miyoo"
			fi
			RA_DIR="/mnt/SDCARD/RetroArch"
			cd "$RA_DIR"
			HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$ROM_FILE"
		fi
		;;
	
	*)
		if setting_get "expertRA" || [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
			export RA_BIN="retroarch"
		else
			export RA_BIN="ra32.miyoo"
		fi
		RA_DIR="/mnt/SDCARD/RetroArch"
		cd "$RA_DIR"

		HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$ROM_FILE"

		;;
		
esac

kill -9 $(pgrep -f enforceSmartCPU.sh)
log_message "-----Closing Emulator-----" -v

auto_regen_tmp_update
