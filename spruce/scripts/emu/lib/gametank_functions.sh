#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#
# Provides:
#   run_gametank_standalone

# GameTankEmulator writes the cartridge saves (.sav, .xor, .gtrcfg) next to the
# ROM it was given, so the ROM is staged into Saves/gametank and run from there.
run_gametank_standalone() {
	if [ "$PLATFORM" = "A30" ]; then
		GTE_DIR="$EMU_DIR/gametank-a30"
		export GTE_ROTATE=270
	else
		GTE_DIR="$EMU_DIR/gametank"
	fi

	SAVE_DIR="/mnt/SDCARD/Saves/gametank"
	mkdir -p "$SAVE_DIR"
	export HOME="$SAVE_DIR"
	export XDG_DATA_HOME="$SAVE_DIR"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"

	ROM_NAME="$(basename "${ROM_FILE%.*}").gtr"
	ROM_PATH="$SAVE_DIR/$ROM_NAME"
	case "$ROM_FILE" in
		*.zip)
			TEMP_ROM=$(mktemp -d)
			"$(get_python_path)" -c "
import zipfile, sys
with zipfile.ZipFile(sys.argv[1]) as z: z.extractall(sys.argv[2])
" "$ROM_FILE" "$TEMP_ROM"
			cp -f "$(find "$TEMP_ROM" -type f -iname '*.gtr' | head -1)" "$ROM_PATH"
			rm -rf "$TEMP_ROM"
			;;
		*.7z)
			7zr e "$ROM_FILE" -so > "$ROM_PATH"
			;;
		*)
			cmp -s "$ROM_FILE" "$ROM_PATH" || cp -f "$ROM_FILE" "$ROM_PATH"
			;;
	esac

	[ -f /opt/inttools/gamecontrollerdb.txt ] && \
		export SDL_GAMECONTROLLERCONFIG_FILE=/opt/inttools/gamecontrollerdb.txt
	case "$PLATFORM" in
		"Anbernic"*) export_sdl_gamecontroller_map positional ;;
	esac

	cd "$GTE_DIR"
	log_message "gametank_functions.sh: launching $ROM_PATH"
	./GameTankEmulator "$ROM_PATH" > "$(emu_log_file)" 2>&1
}
