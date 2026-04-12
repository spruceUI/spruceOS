#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   PCSX_BIN  (from platform .cfg)
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_pcsx_standalone

run_pcsx_standalone() {
	export LD_LIBRARY_PATH="$EMU_DIR/libs:$LD_LIBRARY_PATH"
	export HOME="$EMU_DIR"

	mkdir -p "$HOME/.pcsx/bios"
	mount --bind /mnt/SDCARD/BIOS "$HOME/.pcsx/bios"

	cd "$HOME"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh

	"./${PCSX_BIN:-pcsx}" -cdfile "$ROM_FILE" > $(emu_log_file) 2>&1

	umount "$HOME/.pcsx/bios" 2>/dev/null
}
