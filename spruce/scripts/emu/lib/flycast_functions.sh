#!/bin/sh

# Requires globals:
#   ROM_FILE
#   PLATFORM
#   CORE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_flycast_standalone

set_ui_scale() {

	CFG=/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg

	if [ "$CORE" = "Flycast-stock" ]; then
		SCALING=100
	else
		case "$PLATFORM" in
			"Flip"|"Pixel2") SCALING=70 ;;
			"Brick") SCALING=120 ;;
			*) SCALING=100 ;;
		esac
	fi

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
	/mnt/SDCARD/spruce/scripts/asound-setup.sh

	if [ "$CORE" = "Flycast-stock" ]; then
		./flycast-stock "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	else
		./flycast "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	fi

	umount $HOME/bios
	umount $HOME/data
}
