#!/bin/sh

# Requires globals:
#   ROM_FILE
#   PLATFORM
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_flycast_standalone

run_flycast_standalone() {
	export HOME="/mnt/SDCARD/Emu/DC"
	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$HOME/lib64"

	mkdir -p "$HOME/.local/share/flycast"
	mkdir -p "/mnt/SDCARD/BIOS/dc"
	mount --bind /mnt/SDCARD/BIOS/dc $HOME/.local/share/flycast

	cd "$HOME"
	./flycast "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1

	umount $HOME/.local/share/flycast
}