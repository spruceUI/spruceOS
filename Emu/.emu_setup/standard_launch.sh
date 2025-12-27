#!/bin/sh
# One Emu launch.sh to rule them all!
# This script is Ry's baby, please treat her well -Sun
# Ry 2024-09-24

##### DEFINE BASE VARIABLES #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

export_ld_library_path

log_message "-----Launching Emulator-----"
log_message "trying: $0 $@"

export LOG_DIR=/mnt/SDCARD/Saves/spruce
export EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
export EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
export EMU_JSON_PATH="${EMU_DIR}/config.json"
export GAME="$(basename "$1")"
export MODE="$(get_cpu_mode_from_emu_json)"
ROM_FILE="$(echo "$1" | sed 's|/media/SDCARD0/|/mnt/SDCARD/|g')"
export ROM_FILE="$(readlink -f "$ROM_FILE")"

. /mnt/SDCARD/Emu/.emu_setup/lib/general_functions.sh
. /mnt/SDCARD/Emu/.emu_setup/lib/led_functions.sh
. /mnt/SDCARD/Emu/.emu_setup/lib/network_functions.sh
. /mnt/SDCARD/Emu/.emu_setup/lib/gtt_functions.sh
. /mnt/SDCARD/Emu/.emu_setup/lib/ra_functions.sh

 ########################
##### MAIN EXECUTION #####
 ########################

set_emu_core_from_emu_json
if [ -z "$CORE" ] || [ "$CORE" = "null" ]; then	use_default_emulator ; fi
get_core_override
get_mode_override
set_cpu_mode
record_session_start_time
handle_network_services
led_effect &
flag_add 'emulator_launched'


case $EMU_NAME in

	"DC"|"NAOMI")
		if [ "$CORE" = "Flycast-standalone" ]; then
			. /mnt/SDCARD/Emu/.emu_setup/lib/flycast_functions.sh
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
		. /mnt/SDCARD/Emu/.emu_setup/lib/media_functions.sh
		run_ffplay
		;;

	"NDS")
		. /mnt/SDCARD/Emu/.emu_setup/lib/drastic_functions.sh
		run_drastic
		;;

	"N64")
		if [ "$CORE" = "mupen64plus-standalone" ]; then
			. /mnt/SDCARD/Emu/.emu_setup/lib/mupen_functions.sh
			run_mupen_standalone
		else
			load_n64_controller_profile
			run_retroarch
			save_custom_n64_controller_profile
		fi
		;;

	"OPENBOR")
		. /mnt/SDCARD/Emu/.emu_setup/lib/openbor_functions.sh
		run_openbor
		;;

	"PICO8")			
		. /mnt/SDCARD/Emu/.emu_setup/lib/pico8_functions.sh
		load_pico8_control_profile
		run_pico8
		;;

	"PORTS")
		. /mnt/SDCARD/Emu/.emu_setup/lib/ports_functions.sh
		run_port
		;;

	"PSP")
		. /mnt/SDCARD/Emu/.emu_setup/lib/ppsspp_functions.sh
		[ ! -d "/mnt/SDCARD/.config" ] && move_dotconfig_into_place
		load_ppsspp_configs
		run_ppsspp
		save_ppsspp_configs
		;;

	"SATURN")
		if [ "$CORE" = "yabasanshiro-standalone-bios" ] || [ "$CORE" = "yabasanshiro-standalone-hle" ]; then
			. /mnt/SDCARD/Emu/.emu_setup/lib/yaba_functions.sh
			run_yabasanshiro
		else
			export CORE="yabasanshiro"
			run_retroarch
		fi
		;;

	*)
		run_retroarch
		;;
esac

kill -9 $(pgrep -f enforceSmartCPU.sh) || true
record_session_end_time
calculate_current_session_duration
update_gtt

log_message "-----Closing Emulator-----"

auto_regen_tmp_update
