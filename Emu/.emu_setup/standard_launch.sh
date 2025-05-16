#!/bin/sh
# One Emu launch.sh to rule them all!
# This svript is Ry's baby, please treat her well -Sun
# Ry 2024-09-24

##### DEFINE BASE VARIABLES #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh

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
export CUSTOM_DEF_FILE="$EMU_DIR/default.opt"

##### GENERAL FUNCTIONS #####

import_launch_options() {
	if [ -f "$DEF_FILE" ]; then
		. "$DEF_FILE"
	elif [ -f "$CUSTOM_DEF_FILE" ]; then
		. "$CUSTOM_DEF_FILE"
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

##### TIME TRACHKING FUNCTIONS #####

export START_TIME_PATH="/tmp/start_time"
export END_TIME_PATH="/tmp/end_time"
export DURATION_PATH="/tmp/session_duration"
export TRACKER_JSON_PATH="/mnt/SDCARD/Saves/spruce/gtt.json"
export MISSION_JSON_PATH="/mnt/SDCARD/Saves/spruce/bitpal_data/active_missions.json"

record_session_start_time() {
    date +%s > "$START_TIME_PATH"
}

record_session_end_time() {
    date +%s > "$END_TIME_PATH"
}

calculate_current_session_duration() {
    START_TIME=$(cat "$START_TIME_PATH")
    END_TIME=$(cat "$END_TIME_PATH")
    DURATION=$(( END_TIME - START_TIME ))
    echo "$DURATION" > "$DURATION_PATH"
}

update_gtt_and_bp() {
    # Initialize GTT JSON if needed
    if [ ! -f "$TRACKER_JSON_PATH" ] || [ -z "$(cat "$TRACKER_JSON_PATH")" ]; then
        jq -n '{ games: {} }' > "$TRACKER_JSON_PATH"
    fi

	# take care of pesky SDCARD vs sdcard
	ROM_FILE="$(echo "$ROM_FILE" | sed 's|/mnt/sdcard|/mnt/SDCARD|')"

    GTT_GAME_NAME="${GAME%.*} ($EMU_NAME)"
    SESSION_DURATION="$(cat "$DURATION_PATH")"
    END_TIME="$(cat "$END_TIME_PATH")"

    PREVIOUS_PLAYTIME="$(jq --arg game "$GTT_GAME_NAME" -r '.games[$game].playtime_seconds // 0' "$TRACKER_JSON_PATH")"
    NEW_PLAYTIME=$((PREVIOUS_PLAYTIME + SESSION_DURATION))

    OLD_NUM_SESSIONS="$(jq --arg game "$GTT_GAME_NAME" -r '.games[$game].sessions_played // 0' "$TRACKER_JSON_PATH")"
    NEW_NUM_SESSIONS=$((OLD_NUM_SESSIONS + 1))

	# update Game Time Tracker
	tmpfile=$(mktemp)
    jq --arg game "$GTT_GAME_NAME" \
	   --arg rompath "$ROM_FILE" \
       --argjson newTime "$NEW_PLAYTIME" \
       --argjson numPlays "$NEW_NUM_SESSIONS" \
       --arg emu "$EMU_NAME" \
       --argjson lastPlayed "$END_TIME" \
       '.games[$game] += {
	   	   rompath: $rompath,
           console: $emu,
           playtime_seconds: $newTime,
           sessions_played: $numPlays,
           last_played: $lastPlayed
       }' "$TRACKER_JSON_PATH" > "$tmpfile" && mv "$tmpfile" "$TRACKER_JSON_PATH"

	# update any BitPal missions for the given rompath
	for i in $(jq -r --arg path "$ROM_FILE" '
		.missions
		| to_entries[]
		| select(.value.rompath == $path)
		| .key
	' "$MISSION_JSON"); do

		PREVIOUS_PLAYTIME="$(get_mission_time_spent "$i")"
    	NEW_PLAYTIME=$((PREVIOUS_PLAYTIME + SESSION_DURATION))
		set_mission_time_spent "$i" "$NEW_PLAYTIME"

		MISSION_DURATION="$(get_mission_duration "$i")"
		MISSION_DURATION_SECONDS=$((60 * MISSION_DURATION))
		if [ "$NEW_PLAYTIME" -ge "$MISSION_DURATION_SECONDS" ]; then

			current_xp=$(get_bitpal_xp)
			gained_xp=$(get_mission_xp_reward "$i")
			new_current_xp=$((current_xp + gained_xp))
			set_bitpal_xp "$new_current_xp"

			set_mission_enddate "$i" "$(date +%s)"
			move_mission_to_completed_json "$i"
		fi

	done

	# clean up temp files to prevent accidental cross-pollination
	rm "$START_TIME_PATH" "$END_TIME_PATH" "$DURATION_PATH" 2>/dev/null
}


##### EMULATOR LAUNCH FUNCTIONS #####

run_ffplay() {
	export HOME=$EMU_DIR
	cd $EMU_DIR
	if [ "$PLATFORM" = "A30" ]; then
		export PATH="$EMU_DIR"/bin:"$PATH"
		export LD_LIBRARY_PATH="$EMU_DIR"/libs:/usr/miyoo/lib:/usr/lib:"$LD_LIBRARY_PATH"
		ffplay -vf transpose=2 -fs -i "$ROM_FILE" > ffplay.log 2>&1
	else
		export PATH="$EMU_DIR"/bin64:"$PATH"
		export LD_LIBRARY_PATH="$LD_LIBRARY_PATH":"$EMU_DIR"/lib64
		/mnt/SDCARD/spruce/bin64/gptokeyb -k "ffplay" -c "./bin64/ffplay.gptk" &
		sleep 1
		ffplay -x $DISPLAY_WIDTH -y $DISPLAY_HEIGHT -fs -i "$ROM_FILE" > ffplay.log 2>&1 # trimui devices crash after about 30 seconds when not outputting to a log???
		kill -9 "$(pidof gptokeyb)"
	fi
}

run_drastic() {
	export HOME=$EMU_DIR
	cd $EMU_DIR

	if [ "$PLATFORM" = "A30" ]; then

		[ -d "$EMU_DIR/backup-32" ] && mv "$EMU_DIR/backup-32" "$EMU_DIR/backup"
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
		[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-32"

	else # 64-bit platform

		[ -d "$EMU_DIR/backup-64" ] && mv "$EMU_DIR/backup-64" "$EMU_DIR/backup"
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
		
		if [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then # using specific platforms here in case we ever support a device on a different chipset in the future
			export LD_PRELOAD=./lib64_a133p/libSDL2-2.0.so.0 ### this option affects screen layouts and may be beneficial for the TSP
		elif [ "$PLATFORM" = "Flip" ]; then
			export LD_PRELOAD=./lib64_rk3566/libSDL2-2.0.so.0
		fi
		
		[ "$PLATFORM" = "Flip" ] || export SDL_AUDIODRIVER=dsp ### this option breaks the flip but may help with stuttering on the A133s
		./drastic64 "$ROM_FILE"
		[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-64"
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
		./OpenBOR_Brick "$ROM_FILE"
	elif [ "$PLATFORM" = "Flip" ]; then
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME
		./OpenBOR_Flip "$ROM_FILE"
	else # assume A30
		export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib
		if [ "$GAME" = "Final Fight LNS.pak" ]; then
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

	# set 64-bit wget for BBS
	if ! [ "$PLATFORM" = "A30" ]; then
		WGET_PATH="$HOME"/bin64:
	fi

	export HOME="$EMU_DIR"
	export PATH=$WGET_PATH"$HOME"/bin:$PATH:"/mnt/SDCARD/BIOS"

	if setting_get "pico8_stretch"; then
		case "$PLATFORM" in
			"A30") SCALING="-draw_rect 0,0,$DISPLAY_HEIGHT,$DISPLAY_WIDTH" ;; # handle A30's rotated screen
			*) SCALING="-draw_rect 0,0,$DISPLAY_WIDTH,$DISPLAY_HEIGHT" ;;
		esac
	else
		SCALING=""
	fi

	cd "$HOME"

	if [ "$PLATFORM" = "A30" ]; then
		export SDL_VIDEODRIVER=mali
		export SDL_JOYSTICKDRIVER=a30
		PICO8_BINARY="pico8_dyn"
		sed -i 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt"
	else
		PICO8_BINARY="pico8_64"
		sed -i 's|^transform_screen 135$|transform_screen 0|' "$HOME/.lexaloffle/pico-8/config.txt"
	fi

	if [ "${GAME##*.}" = "splore" ]; then
		check_and_connect_wifi
		$PICO8_BINARY -splore -width $DISPLAY_WIDTH -height $DISPLAY_HEIGHT -root_path "/mnt/SDCARD/Roms/PICO8/" $SCALING
	else
		$PICO8_BINARY -width $DISPLAY_WIDTH -height $DISPLAY_HEIGHT -scancodes -run "$ROM_FILE" $SCALING
	fi
	sync

	# send signal USR1 to joystickinput to switch to ANALOG MODE
	killall -q -USR1 joystickinput
}

load_pico8_control_profile() {
	HOME="$EMU_DIR"
	P8_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"
	CONTROL_PROFILE="$(setting_get "pico8_control_profile")"

	case "$PLATFORM" in
		"A30")
			if [ "$CONTROL_PROFILE" = "Steward" ]; then
				export LD_LIBRARY_PATH="$HOME"/lib-stew:$LD_LIBRARY_PATH
			else
				export LD_LIBRARY_PATH="$HOME"/lib-cine:$LD_LIBRARY_PATH
			fi
			;;
		"Flip")
			export LD_LIBRARY_PATH="$HOME"/lib-Flip:$LD_LIBRARY_PATH
			;;
		"Brick" | "SmartPro")
			export LD_LIBRARY_PATH="$HOME"/lib-trimui:$LD_LIBRARY_PATH
			;;
	esac

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

extract_game_dir(){
    # long-term come up with better method.
    # this is short term for testing
    gamedir_line=$(grep "^GAMEDIR=" "$ROM_FILE")
    # If gamedir_name ends with a slash, remove the slash
    gamedir_line="${gamedir_line%/}"
    # Extract everything after the last '/' in the GAMEDIR line and assign it to game_dir
    game_dir="/mnt/SDCARD/Roms/PORTS/${gamedir_line##*/}"
    # If game_dir ends with a quote, remove the quote
    echo "${game_dir%\"}"
}

is_retroarch_port() {
    # Check if the file contains "retroarch"
    if grep -q "retroarch" "$ROM_FILE"; then
        return 1;
    else
        return 0;
    fi
}

set_port_mode() {
    rm "/mnt/SDCARD/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
    if [ "$PORT_CONTROL" = "X360" ]; then
        cp "/mnt/SDCARD/Emu/PORTS/gamecontrollerdb_360.txt" "/mnt/SDCARD/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
    else
        cp "/mnt/SDCARD/Emu/PORTS/gamecontrollerdb_nintendo.txt" "/mnt/SDCARD/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
    fi
}

run_port() {
	if [ "$PLATFORM" = "Flip" ] || [ "$PLATFORM" = "Brick" ]; then
        /mnt/SDCARD/spruce/flip/bind-new-libmali.sh
        set_port_mode

        is_retroarch_port
        if [[ $? -eq 1 ]]; then
            PORTS_DIR=/mnt/SDCARD/Roms/PORTS
            cd /mnt/SDCARD/RetroArch/
            export HOME="/mnt/SDCARD/Saves/flip/home"
            export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib/:/usr/lib:/mnt/SDCARD/spruce/flip/muOS/usr/lib/:/mnt/SDCARD/spruce/flip/muOS/lib/:/usr/lib32:/mnt/SDCARD/spruce/flip/lib32/:/mnt/SDCARD/spruce/flip/muOS/usr/lib32/:$LD_LIBRARY_PATH"
            export PATH="/mnt/SDCARD/spruce/flip/bin/:$PATH"
             "$ROM_FILE" &> /mnt/SDCARD/Saves/spruce/port.log
        else
            PORTS_DIR=/mnt/SDCARD/Roms/PORTS
            cd $PORTS_DIR
            export HOME="/mnt/SDCARD/Saves/flip/home"
            export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib/:/usr/lib:/mnt/SDCARD/spruce/flip/muOS/usr/lib/:/mnt/SDCARD/spruce/flip/muOS/lib/:/usr/lib32:/mnt/SDCARD/spruce/flip/lib32/:/mnt/SDCARD/spruce/flip/muOS/usr/lib32/:$LD_LIBRARY_PATH"
            export PATH="/mnt/SDCARD/spruce/flip/bin/:$PATH"
            "$ROM_FILE" &> /mnt/SDCARD/Saves/spruce/port.log
        fi
        
        /mnt/SDCARD/spruce/flip/unbind-new-libmali.sh
    else
        PORTS_DIR=/mnt/SDCARD/Roms/PORTS
        cd $PORTS_DIR
        /bin/sh "$ROM_FILE" 
    fi
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

	PPSSPP_CMDLINE="--fullscreen"
	if setting_get "ppsspp_pause_exit"; then
		PPSSPP_CMDLINE="$PPSSPP_CMDLINE --pause-menu-exit"
	fi

	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"
	case "$PLATFORM" in
		"A30") PPSSPPSDL="./PPSSPPSDL" ;;
		"Flip") PPSSPPSDL="./PPSSPPSDL_Flip" ;;
		"Brick"|"SmartPro") PPSSPPSDL="./PPSSPPSDL_TrimUI" ;;
	esac
	"$PPSSPPSDL" "$ROM_FILE" "$PPSSPP_CMDLINE"
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

	case "$PLATFORM" in
		"Brick" | "SmartPro" )
			export RA_BIN="ra64.trimui_$PLATFORM"
			if [ "$CORE" = "uae4arm" ]; then
				export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
			elif [ "$CORE" = "genesis_plus_gx" ] && [ "$PLATFORM" = "SmartPro" ] && \
				setting_get "genesis_plus_gx_wide"; then
				CORE="genesis_plus_gx_wide"
			fi
			# TODO: remove this once profile is set up
			export LD_LIBRARY_PATH=$EMU_DIR/lib64:$LD_LIBRARY_PATH
		;;
		"Flip" )
			if [ "$CORE" = "yabasanshiro" ]; then
				# "Error(s): /usr/miyoo/lib/libtmenu.so: undefined symbol: GetKeyShm" if you try to use non-Miyoo RA for this core
				export RA_BIN="ra64.miyoo"
			elif setting_get "expertRA" || [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
				export RA_BIN="retroarch-flip"
			else
				export RA_BIN="ra64.miyoo"
			fi
			if [ "$CORE" = "easyrpg" ]; then
				export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
			elif [ "$CORE" = "yabasanshiro" ]; then
				export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
			fi
		;;
		"A30" )
			# handle different version of ParaLLEl N64 core and flycast xtreme core for A30
			if [ "$CORE" = "parallel_n64" ]; then
				CORE="km_parallel_n64_xtreme_amped_turbo"
			elif [ "$CORE" = "flycast_xtreme" ]; then
				CORE="km_flycast_xtreme"
			fi

			if setting_get "expertRA" || [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
				export RA_BIN="retroarch"
			else
				export RA_BIN="ra32.miyoo"
			fi
		;;
	esac

	RA_DIR="/mnt/SDCARD/RetroArch"
	cd "$RA_DIR"

	if [ "$PLATFORM" = "A30" ]; then
		CORE_DIR="$RA_DIR/.retroarch/cores"
	else # 64-bit device
		CORE_DIR="$RA_DIR/.retroarch/cores64"
	fi

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

	#Swap below if debugging new cores
	#HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v --log-file /mnt/SDCARD/Saves/retroarch.log -L "$CORE_PATH" "$ROM_FILE"
	HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$CORE_PATH" "$ROM_FILE"
}

ready_architecture_dependent_states() {
	STATES="/mnt/SDCARD/Saves/states"
	if [ "$PLATFORM" = "A30" ]; then 
		[ -d "$STATES/RACE-32" ] && mv "$STATES/RACE-32" "$STATES/RACE"
		[ -d "$STATES/fake-08-32" ] && mv "$STATES/fake-08-32" "$STATES/fake-08"
		[ -d "$STATES/PCSX-ReARMed-32" ] && mv "$STATES/PCSX-ReARMed-32" "$STATES/PCSX-ReARMed"
		[ -d "$STATES/ChimeraSNES-32" ] && mv "$STATES/ChimeraSNES-32" "$STATES/ChimeraSNES"

	else # 64-bit device
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
		[ -d "$STATES/PCSX-ReARMed" ] && mv "$STATES/PCSX-ReARMed" "$STATES/PCSX-ReARMed-32"
		[ -d "$STATES/ChimeraSNES" ] && mv "$STATES/ChimeraSNES" "$STATES/ChimeraSNES-32"

	else # 64-bit device
		[ -d "$STATES/RACE" ] && mv "$STATES/RACE" "$STATES/RACE-64"
		[ -d "$STATES/fake-08" ] && mv "$STATES/fake-08" "$STATES/fake-08-64"
		[ -d "$STATES/PCSX-ReARMed" ] && mv "$STATES/PCSX-ReARMed" "$STATES/PCSX-ReARMed-64"
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

run_mupen_standalone() {

	export HOME="$EMU_DIR/mupen64plus"
	export XDG_CONFIG_HOME="$HOME"
	export XDG_DATA_HOME="$HOME"
	export LD_LIBRARY_PATH="$HOME:$LD_LIBRARY_PATH"

	cd "$HOME"

	sed -i "s|^ScreenWidth *=.*|ScreenWidth = $DISPLAY_WIDTH|" "mupen64plus.cfg"
	sed -i "s|^ScreenHeight *=.*|ScreenHeight = $DISPLAY_HEIGHT|" "mupen64plus.cfg"

	case "$ROM_FILE" in
	*.n64 | *.v64 | *.z64)
		ROM_PATH="$ROM_FILE"
		;;
	*.zip | *.7z)
		TEMP_ROM=$(mktemp)
		ROM_PATH="$TEMP_ROM"
		7zr e "$ROM_FILE" -so >"$TEMP_ROM"
		;;
	esac

	[ "$PLATFORM" = "Flip" ] && echo "-1" > /sys/class/miyooio_chr_dev/joy_type
	./gptokeyb2 "mupen64plus" -c "./defkeys.gptk" &
	sleep 0.3
	./mupen64plus "$ROM_PATH"
	kill -9 $(pidof gptokeyb2)

	rm -f "$TEMP_ROM"
}

run_yabasanshiro() {
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
	export HOME="$EMU_DIR"
	cd "$HOME"
	SATURN_BIOS="/mnt/SDCARD/BIOS/saturn_bios.bin"
	case "$PLATFORM" in
		"Flip") YABASANSHIRO="./yabasanshiro" ;;
		"Brick"|"SmartPro") YABASANSHIRO="./yabasanshiro.trimui" ;; # todo: add yabasanshiro-sa for trimui devices
	esac
	if [ -f "$SATURN_BIOS" ] && [ "$CORE" = "sa_bios" ]; then
		$YABASANSHIRO -r 3 -i "$ROM_FILE" -b "$SATURN_BIOS" >./log.txt 2>&1
	else
		$YABASANSHIRO -r 3 -i "$ROM_FILE" >./log.txt 2>&1
	fi
}

run_flycast_standalone() {
	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR/lib64"
	export HOME="$EMU_DIR"

	mkdir -p "$EMU_DIR/.local/share/flycast"
	mkdir -p "/mnt/SDCARD/BIOS/dc"
	mount --bind /mnt/SDCARD/BIOS/dc $EMU_DIR/.local/share/flycast

	cd "$EMU_DIR"
	./flycast "$ROM_FILE"

	umount $EMU_DIR/.local/share/flycast
}

 ########################
##### MAIN EXECUTION #####
 ########################

import_launch_options
set_cpu_mode
record_session_start_time
handle_network_services

flag_add 'emulator_launched'

# Sanitize the rom path
ROM_FILE="$(echo "$1" | sed 's|/media/SDCARD0/|/mnt/SDCARD/|g')"
export ROM_FILE="$(readlink -f "$ROM_FILE")"

case $EMU_NAME in
	"DC")
		if [ "$CORE" = "flycast_xtreme" ] && [ ! "$PLATFORM" = "A30" ]; then
			run_flycast_standalone
		else
			run_retroarch
		fi
		;;
	"MEDIA")
		run_ffplay
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
		[ ! -d "/mnt/SDCARD/.config" ] && move_dotconfig_into_place
		load_ppsspp_configs
		run_ppsspp
		save_ppsspp_configs
		;;
	"SATURN")
		if [ "$CORE" = "sa_hle" ] || [ "$CORE" = "sa_bios" ]; then
			run_yabasanshiro
		else
			run_retroarch
		fi
		;;
	"N64")
			if [ "$CORE" = "mupen64plus" ] && [ ! "$PLATFORM" = "A30" ]; then
				run_mupen_standalone
			else
				load_n64_controller_profile
				ready_architecture_dependent_states
				run_retroarch
				stash_architecture_dependent_states
				save_custom_n64_controller_profile
			fi
		;;
	*)
		ready_architecture_dependent_states
		run_retroarch
		stash_architecture_dependent_states
		;;
esac

kill -9 $(pgrep -f enforceSmartCPU.sh)
record_session_end_time
calculate_current_session_duration
update_gtt_and_bp
log_message "-----Closing Emulator-----" -v

auto_regen_tmp_update
