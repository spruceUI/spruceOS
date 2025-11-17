#!/bin/sh
# One Emu launch.sh to rule them all!
# This script is Ry's baby, please treat her well -Sun
# Ry 2024-09-24

##### DEFINE BASE VARIABLES #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

log_message "-----Launching Emulator-----"
log_message "trying: $0 $@"

export EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
export EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
export EMU_JSON_PATH="${EMU_DIR}/config.json"
export GAME="$(basename "$1")"
export MODE="$(jq -r '.menuOptions.Governor.selected' "$EMU_JSON_PATH")"

RETROARCH_CFG="/mnt/SDCARD/spruce/settings/platform/retroarch-${PLATFORM}.cfg"

log_message "---DEBUG---: standard_launch.sh checkpoint 1" -v

case "$EMU_NAME" in
    DC|NAOMI|N64|PS)
        if [ "$PLATFORM" = "A30" ]; then
            export CORE="$(jq -r '.menuOptions.Emulator_A30.selected' "$EMU_JSON_PATH")"
        else
            export CORE="$(jq -r '.menuOptions.Emulator_64.selected' "$EMU_JSON_PATH")"
        fi
        ;;
    NDS)
        case "$PLATFORM" in
            Flip)
                export CORE="$(jq -r '.menuOptions.Emulator_Flip.selected' "$EMU_JSON_PATH")"
                ;;
            Brick)
                export CORE="$(jq -r '.menuOptions.Emulator_Brick.selected' "$EMU_JSON_PATH")"
                ;;
        esac
        ;;
    *)
        export CORE="$(jq -r '.menuOptions.Emulator.selected' "$EMU_JSON_PATH")"
        ;;
esac

log_message "---DEBUG---: standard_launch.sh checkpoint 2" -v

##### GENERAL FUNCTIONS #####

use_default_emulator() {
	export CORE="$(jq -r '.default_emulator' "$EMU_JSON_PATH")"
	log_message "Using default core of $CORE to run $EMU_NAME"
}

get_core_override() {
	local core_override="$(jq -r --arg game "$GAME" '.menuOptions.Emulator.overrides[$game]' "$EMU_JSON_PATH")"
	if [ -n "$core_override" ] && [ "$core_override" != "null" ]; then
		export CORE=$core_override
	fi
}

get_mode_override() {
	local mode_override="$(jq -r --arg game "$GAME" '.menuOptions.Governor.overrides[$game]' "$EMU_JSON_PATH")"
	if [ -n "$mode_override" ] && [ "$mode_override" != "null" ]; then
		export MODE=$mode_override
	fi
}

set_cpu_mode() {
	if [ "$MODE" = "Overclock" ]; then
		if [ "$EMU_NAME" = "NDS" ]; then
			( sleep 33 && set_overclock ) &
		else
			set_overclock
		fi
	fi

	if [ "$MODE" != "Overclock" ] && [ "$MODE" != "Performance" ]; then
		export scaling_min_freq="$(jq -r '.scaling_min_freq' "$EMU_JSON_PATH")"
		/mnt/SDCARD/spruce/scripts/enforceSmartCPU.sh &
	fi
}

handle_network_services() {

	wifi_needed=false
	syncthing_enabled=false
	wifi_connected=false
	disable_wifi_in_game="$(get_config_value '.menuOptions."Battery Settings".disableWifiInGame.selected' "False")"
	disable_net_serv_in_game="$(get_config_value '.menuOptions."Battery Settings".disableNetworkServicesInGame.selected' "False")"

	##### RAC Check #####
	if [ "$disable_wifi_in_game" = "False" ] && grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
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
	if [ "$disable_wifi_in_game" = "True" ] || [ "$disable_net_serv_in_game" = "True" ]; then
		/mnt/SDCARD/spruce/scripts/networkservices.sh off
		
		if [ "$disable_wifi_in_game" = "True" ]; then
			if ifconfig wlan0 | grep "inet addr:" >/dev/null 2>&1; then
				ifconfig wlan0 down &
			fi
			killall wpa_supplicant
			killall udhcpc
		fi
	fi
}

log_message "---DEBUG---: standard_launch.sh checkpoint 3" -v

##### TIME TRACKING FUNCTIONS #####

export START_TIME_PATH="/tmp/start_time"
export END_TIME_PATH="/tmp/end_time"
export DURATION_PATH="/tmp/session_duration"
export TRACKER_JSON_PATH="/mnt/SDCARD/Saves/spruce/gtt.json"

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

update_gtt() {
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


	# clean up temp files to prevent accidental cross-pollination
	rm "$START_TIME_PATH" "$END_TIME_PATH" "$DURATION_PATH" 2>/dev/null
}


log_message "---DEBUG---: standard_launch.sh checkpoint 4" -v

##### EMULATOR LAUNCH FUNCTIONS #####

### MEDIA ###

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


### NDS ###

run_drastic() {
	export HOME=$EMU_DIR
	cd $EMU_DIR

	if [ "$PLATFORM" = "A30" ]; then # only Steward is available.

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

		./drastic32 "$ROM_FILE"
		# remove soft link and resume joystickinput
		rm /dev/ttyS0
		killall -q -CONT joystickinput
		[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-32"

	else # 64-bit platform

		[ -d "$EMU_DIR/backup-64" ] && mv "$EMU_DIR/backup-64" "$EMU_DIR/backup"
		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/lib64
		
		if [ "$PLATFORM" = "Brick" ]; then
			if [ "$CORE" = "DraStic-Steward" ]; then
				kill_runner
				LD_LIBRARY_PATH=/usr/trimui/lib ./runner&
				sleep 1
				export SDL_VIDEODRIVER=NDS
				./lib32_Brick/ld-linux-armhf.so.3 --library-path lib32_Brick ./drastic32 "$ROM_FILE" > /mnt/SDCARD/Saves/spruce/drastic-steward-brick.log 2>&1
				sync
				kill_runner
			else 

				##### TODO: HOOK UP TRNGAJE's DRASTIC FOR BRICK

				./drastic64 "$ROM_FILE" > /mnt/SDCARD/Saves/spruce/drastic-og-brick.log 2>&1
			fi

		elif [ "$PLATFORM" = "SmartPro" ]; then

			##### TODO: HOOK UP CORE SWITCH B/T TRNGAJE AND OG DRASTIC on SMART PRO; no Steward available

			export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOME/lib64_a133p"
			export SDL_AUDIODRIVER=dsp
			./drastic64 "$ROM_FILE" > /mnt/SDCARD/Saves/spruce/drastic-og-smartpro.log 2>&1

		elif [ "$PLATFORM" = "Flip" ]; then

			if [ -d /usr/l32 ] && [ "$CORE" = "DraStic-Steward" ]; then
				export SDL_VIDEODRIVER=NDS
				export LD_LIBRARY_PATH="$HOME/lib32_Flip:/usr/lib32:$LD_LIBRARY_PATH"
				./drastic32 "$ROM_FILE" > /mnt/SDCARD/Saves/spruce/drastic-steward-flip.log 2>&1

			elif [ "$CORE" = "DraStic-trngaje" ]; then
				export LD_LIBRARY_PATH="$HOME/lib64_Flip:$LD_LIBRARY_PATH"
				mv ./drastic64 ./drastic
				./drastic "$ROM_FILE" > /mnt/SDCARD/Saves/spruce/drastic-trngaje-flip.log 2>&1
				mv ./drastic ./drastic64
			else
				# if overlay mount of /usr fails, fall back to original DraStic instead of Steward's
				./drastic64 "$ROM_FILE" > /mnt/SDCARD/Saves/spruce/drastic-og-flip.log
			fi
		fi
		
		[ -d "$EMU_DIR/backup" ] && mv "$EMU_DIR/backup" "$EMU_DIR/backup-64"
	fi
	sync
}

kill_runner() {
    PID="$(pidof runner)"
    if [ "$PID" != "" ]; then
        kill -9 $PID
    fi
}

load_drastic_configs() {
	DS_DIR="/mnt/SDCARD/Emu/NDS/config"
	cp -f "$DS_DIR/drastic-$PLATFORM.cfg" "$DS_DIR/drastic.cfg"
}

save_drastic_configs() {
	DS_DIR="/mnt/SDCARD/Emu/NDS/config"
	cp -f "$DS_DIR/drastic.cfg" "$DS_DIR/drastic-$PLATFORM.cfg"
}

### OPENBOR ###

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

### PICO8 ###

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

	STRETCH="$(jq -r '.menuOptions.Stretch.selected' "$EMU_JSON_PATH")"
	if [ "$STRETCH" = "True" ]; then
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
	export HOME="$EMU_DIR"
	P8_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"
	CONTROL_PROFILE="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	STEWARD_MODE="$(jq -r '.menuOptions.stewardMode.selected' "$EMU_JSON_PATH")"

	case "$PLATFORM" in
		"A30")
			if [ "$STEWARD_MODE" = "On - A-ⓧ B-ⓞ X-Esc SELECT-Mouse" ]; then
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
		"Doubled - A-ⓧ B-ⓞ Y-ⓧ X-ⓞ")	cp -f "$P8_DIR/sdl_controllers.facebuttons" "$P8_DIR/sdl_controllers.txt" ;;
		"One-hand - A-ⓧ B-ⓞ L1-ⓧ L2-ⓞ")	cp -f "$P8_DIR/sdl_controllers.onehand" 	"$P8_DIR/sdl_controllers.txt" ;;
		"Racing - A-ⓧ B-ⓞ L1-ⓧ R1-ⓞ")	cp -f "$P8_DIR/sdl_controllers.racing" 		"$P8_DIR/sdl_controllers.txt" ;;
		"Doubled II - B-ⓧ A-ⓞ X-ⓧ Y-ⓞ") cp -f "$P8_DIR/sdl_controllers.facebuttons_reverse" "$P8_DIR/sdl_controllers.txt" ;;
		"One-hand II - B-ⓧ A-ⓞ L2-ⓧ L1-ⓞ") cp -f "$P8_DIR/sdl_controllers.onehand_reverse"	"$P8_DIR/sdl_controllers.txt" ;;
		"Racing II - B-ⓧ A-ⓞ R1-ⓧ L1-ⓞ") cp -f "$P8_DIR/sdl_controllers.racing_reverse" 	"$P8_DIR/sdl_controllers.txt" ;;
	esac
}

### PORTS ###

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
	PORT_CONTROL="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
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

### PSP ###

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

	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"
	case "$PLATFORM" in
		"A30") PPSSPPSDL="./PPSSPPSDL" ;;
		"Flip") PPSSPPSDL="./PPSSPPSDL_Flip" ;;
		"Brick"|"SmartPro") PPSSPPSDL="./PPSSPPSDL_TrimUI" ;;
	esac
	"$PPSSPPSDL" "$ROM_FILE" --fullscreen --pause-menu-exit
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

### EVERYTHING ELSE ###

run_retroarch() {

	use_igm="$(get_config_value '.menuOptions."Emulator Settings".raInGameMenu.selected' "True")"
	auto_save="$(get_config_value '.menuOptions."Emulator Settings".raAutoSave.selected' "True")"
	auto_load="$(get_config_value '.menuOptions."Emulator Settings".raAutoLoad.selected' "True")"
	log_message "auto save setting is $auto_save" -v
	log_message "auto load setting is $auto_load" -v

	if [ "$auto_save" = "True" ]; then
	    sed -i 's|savestate_auto_save.*|savestate_auto_save = "true"|' "$RETROARCH_CFG"
	else
	    sed -i 's|savestate_auto_save.*|savestate_auto_save = "false"|' "$RETROARCH_CFG"
	fi
	if [ "$auto_load" = "True" ]; then
	    sed -i 's|savestate_auto_load.*|savestate_auto_load = "true"|' "$RETROARCH_CFG"
	else
	    sed -i 's|savestate_auto_load.*|savestate_auto_load = "false"|' "$RETROARCH_CFG"
	fi

	case "$PLATFORM" in
		"Brick" | "SmartPro" )
			export RA_BIN="ra64.trimui_$PLATFORM"
			if [ "$CORE" = "uae4arm" ]; then
				export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
			elif [ "$CORE" = "genesis_plus_gx" ] && [ "$PLATFORM" = "SmartPro" ]; then
				use_gpgx_wide="$(get_config_value '.menuOptions."Emulator Settings".genesisPlusGXWide.selected' "False")"
				[ "$use_gpgx_wide" = "True" ] && CORE="genesis_plus_gx_wide"
			fi
			# TODO: remove this once profile is set up
			export LD_LIBRARY_PATH=$EMU_DIR/lib64:$LD_LIBRARY_PATH
		;;
		"Flip" )
			if [ "$CORE" = "yabasanshiro" ]; then
				# "Error(s): /usr/miyoo/lib/libtmenu.so: undefined symbol: GetKeyShm" if you try to use non-Miyoo RA for this core
				export RA_BIN="ra64.miyoo"
			elif [ "$use_igm" = "False" ] || [ "$CORE" = "parallel_n64" ]; then
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
			if [ "$use_igm" = "False" ] || [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
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
	PROFILE="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	[ "$PROFILE" = "Classic (R2 + A, B, X, Y)" ] && PROFILE="Classic"
	[ "$PROFILE" = "Action (A, X, Select, R1)" ] && PROFILE="Action"

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
	PROFILE="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	[ "$PROFILE" = "Classic (R2 + A, B, X, Y)" ] && PROFILE="Classic"
	[ "$PROFILE" = "Action (A, X, Select, R1)" ] && PROFILE="Action"
	
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

### N64 ###

run_mupen_standalone() {

	export HOME="$EMU_DIR/mupen64plus"
	export XDG_CONFIG_HOME="$HOME"
	export XDG_DATA_HOME="$HOME"
	export LD_LIBRARY_PATH="$HOME:$LD_LIBRARY_PATH"

	cd "$HOME"

	sed -i "s|^ScreenWidth *=.*|ScreenWidth = $DISPLAY_WIDTH|" "$HOME/.config/mupen64plus/mupen64plus.cfg"
	sed -i "s|^ScreenHeight *=.*|ScreenHeight = $DISPLAY_HEIGHT|" "$HOME/.config/mupen64plus/mupen64plus.cfg"

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

### SATURN ###

run_yabasanshiro() {
	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
	export HOME="$EMU_DIR"
	cd "$HOME"
	SATURN_BIOS="/mnt/SDCARD/BIOS/saturn_bios.bin"
	case "$PLATFORM" in
		"Flip") YABASANSHIRO="./yabasanshiro" ;;
		"Brick"|"SmartPro") YABASANSHIRO="./yabasanshiro.trimui" ;; # todo: add yabasanshiro-sa for trimui devices
	esac
	if [ -f "$SATURN_BIOS" ] && [ "$CORE" = "yabasanshiro-standalone-bios" ]; then
		$YABASANSHIRO -r 3 -i "$ROM_FILE" -b "$SATURN_BIOS" >./log.txt 2>&1
	else
		$YABASANSHIRO -r 3 -i "$ROM_FILE" >./log.txt 2>&1
	fi
}

run_flycast_standalone() {
	export HOME="/mnt/SDCARD/Emu/DC"
	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOME/lib64"

	mkdir -p "$HOME/.local/share/flycast"
	mkdir -p "/mnt/SDCARD/BIOS/dc"
	mount --bind /mnt/SDCARD/BIOS/dc $HOME/.local/share/flycast

	cd "$HOME"
	./flycast "$ROM_FILE"

	umount $HOME/.local/share/flycast
}

log_message "---DEBUG---: standard_launch.sh checkpoint 5" -v

 ########################
##### MAIN EXECUTION #####
 ########################

if [ -z "$CORE" ] || [ "$CORE" = "null" ]; then	use_default_emulator ; fi
get_core_override
get_mode_override
set_cpu_mode
record_session_start_time
handle_network_services

flag_add 'emulator_launched'

# Sanitize the rom path
ROM_FILE="$(echo "$1" | sed 's|/media/SDCARD0/|/mnt/SDCARD/|g')"
export ROM_FILE="$(readlink -f "$ROM_FILE")"

log_message "---DEBUG---: standard_launch.sh checkpoint 6" -v

case $EMU_NAME in

	"DC"|"NAOMI")
		if [ "$CORE" = "Flycast-standalone" ]; then
			run_flycast_standalone
		elif [ ! "$PLATFORM" = "A30" ]; then
			export CORE="flycast"
			run_retroarch
		else
			run_retroarch
		fi
		;;

	"GB"*)
		APPLY_PO="$(get_config_value '.menuOptions."Emulator Settings".perfectOverlays.selected' "False")"
		/mnt/SDCARD/spruce/scripts/applySetting/PerfectOverlays/applyPerfectOs.sh "$APPLY_PO"
		run_retroarch
		;;

	"MEDIA")
		run_ffplay
		;;

	"NDS")
		load_drastic_configs
		run_drastic
		save_drastic_configs
		;;

	"N64")
		if [ "$CORE" = "mupen64plus-standalone" ]; then
			run_mupen_standalone
		else
			load_n64_controller_profile
			ready_architecture_dependent_states
			run_retroarch
			stash_architecture_dependent_states
			save_custom_n64_controller_profile
		fi
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
		if [ "$CORE" = "yabasanshiro-standalone-bios" ] || [ "$CORE" = "yabasanshiro-standalone-hle" ]; then
			run_yabasanshiro
		else
			export CORE="yabasanshiro"
			run_retroarch
		fi
		;;

	*)
		ready_architecture_dependent_states
		run_retroarch
		stash_architecture_dependent_states
		;;
esac

log_message "---DEBUG---: standard_launch.sh checkpoint 7" -v

kill -9 $(pgrep -f enforceSmartCPU.sh)
record_session_end_time
calculate_current_session_duration
update_gtt
log_message "-----Closing Emulator-----" -v

auto_regen_tmp_update
