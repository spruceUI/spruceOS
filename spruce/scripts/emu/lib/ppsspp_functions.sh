#!/bin/sh

# Requires globals:
#   PLATFORM
#   EMU_DIR
#   ROM_FILE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Requires functions:
#   log_message
#
# Provides:
#   move_dotconfig_into_place
#   run_ppsspp
#   load_ppsspp_configs
#   save_ppsspp_configs

move_dotconfig_into_place() {
	if [ -d "/mnt/SDCARD/Emu/.emu_setup/.config" ]; then
		cp -rf "/mnt/SDCARD/Emu/.emu_setup/.config" "/mnt/SDCARD/Saves/.config" && log_message "Copied .config folder into Saves folder."
	else
		log_message "WARNING!!! No .config folder found!"
	fi
}

run_ppsspp() {
	export HOME=/mnt/SDCARD/Saves
	cd $EMU_DIR

	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"
	case "$PLATFORM" in
		"Brick"|"SmartPro") PPSSPPSDL="./PPSSPPSDL_TrimUI" ;;
		*) 					PPSSPPSDL="./PPSSPPSDL_${PLATFORM}" ;;
	esac
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	"$PPSSPPSDL" "$ROM_FILE" --fullscreen --pause-menu-exit > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
}

load_ppsspp_configs() {
	PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
	cp -f "$PSP_DIR/controls-$PLATFORM.ini" "$PSP_DIR/controls.ini"
	cp -f "$PSP_DIR/ppsspp-$PLATFORM.ini" "$PSP_DIR/ppsspp.ini"
}

save_ppsspp_configs() {
	PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
	cp -f "$PSP_DIR/controls.ini" "$PSP_DIR/controls-$PLATFORM.ini"
	cp -f "$PSP_DIR/ppsspp.ini" "$PSP_DIR/ppsspp-$PLATFORM.ini"
}
