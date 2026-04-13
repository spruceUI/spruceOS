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
	case "$PLATFORM" in
		"A30")
			PCSX_LIBDIR="$EMU_DIR/liba30"
			export PCSX_ROTATE=270
			export ALSA_NAME=none
			;;
		"MiyooMini") PCSX_LIBDIR="$EMU_DIR/libmini" ;;
		*)           PCSX_LIBDIR="$EMU_DIR/libs" ;;
	esac
	[ -d "$PCSX_LIBDIR" ] && export LD_LIBRARY_PATH="$PCSX_LIBDIR:$LD_LIBRARY_PATH"
	export HOME="$EMU_DIR"

	mkdir -p "$HOME/.pcsx/bios"
	mount --bind /mnt/SDCARD/BIOS "$HOME/.pcsx/bios"

	cd "$HOME"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh

	"./${PCSX_BIN:-pcsx_64}" -cdfile "$ROM_FILE" -load 1 > $(emu_log_file) 2>&1

	umount "$HOME/.pcsx/bios" 2>/dev/null
}
