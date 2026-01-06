#!/bin/sh

# Requires globals:
#   ROM_FILE
#   PLATFORM
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_flycast_standalone

set_ui_scale() {

	CFG=/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg

	case "$PLATFORM" in
		"Flip") SCALING=70 ;;
		"Brick") SCALING=120 ;;
		*) SCALING=100 ;;
	esac

	sed -i "s/^UIScaling[[:space:]]*=[[:space:]]*.*/UIScaling = $SCALING/" "$CFG"
}

run_flycast_standalone() {

	set_ui_scale

	export HOME="/mnt/SDCARD/Emu/DC"
	export LD_LIBRARY_PATH="$HOME/lib-TrimUI:$LD_LIBRARY_PATH:$HOME/lib64"

	mkdir -p "$HOME/bios"
	mkdir -p "$HOME/data"
	mkdir -p "/mnt/SDCARD/BIOS/dc"
	mount --bind /mnt/SDCARD/BIOS/dc $HOME/bios
	mount --bind /mnt/SDCARD/BIOS/dc $HOME/data

	cd "$HOME"
	./flycast "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1

	umount $HOME/bios
	umount $HOME/data
}