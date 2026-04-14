#!/bin/sh

# Requires globals: EMU_DIR, ROM_FILE, PLATFORM, CORE, LOG_DIR
# Provides: run_advmame

run_advmame() {
	COMMON_DIR="/mnt/SDCARD/Saves/saves/advmame"
	export HOME="/mnt/SDCARD/Saves/saves/advmame/${PLATFORM}"
	mkdir -p "$HOME/.advance"
	
	for file in cheat.dat event.dat hiscore.dat history.dat; do
		if [ -f "$EMU_DIR/$file" ]; then
			[ ! -f "$COMMON_DIR/$file" ] && cp "$EMU_DIR/$file" "$COMMON_DIR/"
			rm "$EMU_DIR/$file"
		fi

		if [ -f "$COMMON_DIR/$file" ]; then
			cp -f "$COMMON_DIR/$file" "$HOME/.advance/"
		fi
	done

	DEF_RC=$EMU_DIR/advmame-${PLATFORM}.rc
	RC_FILE=$HOME/.advance/advmame.rc

	if [ ! -f "$RC_FILE" ] && [ -f "$DEF_RC" ]; then
		cp "$DEF_RC" "$RC_FILE"
	fi

	ADVMAME_LOG="$(emu_log_file)"
	ROM_DIR=$(dirname "$ROM_FILE")

	cd "$EMU_DIR"
	case "$PLATFORM" in
		"SmartPro"|"Brick")
			[ -f "$EMU_DIR/advmame.log" ] && rm "$EMU_DIR/advmame.log"
			export LD_LIBRARY_PATH="/mnt/SDCARD/Persistent/portmaster/PortMaster:$LD_LIBRARY_PATH"
			export SDL_GAMECONTROLLERCONFIG="/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
			export SDL_VIDEODRIVER=mali
			"$EMU_DIR/setalpha" 0
			/mnt/SDCARD/Persistent/portmaster/PortMaster/gptokeyb2 $EMU_DIR/advmame -c "$EMU_DIR/advmame.ini" &
			$EMU_DIR/advmame -dir_rom "$ROM_DIR" "${GAME%.*}" -log
			[ -f "$EMU_DIR/advmame.log" ] && cp "$EMU_DIR/advmame.log" "$ADVMAME_LOG"
			kill -9 $(pidof gptokeyb2) 2>/dev/null
			;;
		"SmartProS"|"Flip")
			[ -f "$EMU_DIR/advmame.log" ] && rm "$EMU_DIR/advmame.log"
			export LD_LIBRARY_PATH="/mnt/SDCARD/Persistent/portmaster/PortMaster:$LD_LIBRARY_PATH"
			export SDL_GAMECONTROLLERCONFIG="/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
			/mnt/SDCARD/Persistent/portmaster/PortMaster/gptokeyb2 $EMU_DIR/advmame -c "$EMU_DIR/advmame.ini" &
			$EMU_DIR/advmame -dir_rom "$ROM_DIR" "${GAME%.*}" -log
			[ -f "$EMU_DIR/advmame.log" ] && cp "$EMU_DIR/advmame.log" "$ADVMAME_LOG"
			kill -9 $(pidof gptokeyb2) 2>/dev/null
			;;
		"Pixel2")
			[ -f "$EMU_DIR/advmame.log" ] && rm "$EMU_DIR/advmame.log"
			export SDL_GAMECONTROLLERCONFIG="/mnt/SDCARD/Emu/PORTS/gamecontrollerdb_nintendo.txt"
			/mnt/SDCARD/spruce/pixel2/bin/gptokeyb2 $EMU_DIR/advmame -c "$EMU_DIR/advmame.ini" &
			$EMU_DIR/advmame -dir_rom "$ROM_DIR" "${GAME%.*}" -log
			[ -f "$EMU_DIR/advmame.log" ] && cp "$EMU_DIR/advmame.log" "$ADVMAME_LOG"
			kill -9 $(pidof gptokeyb2)
			;;
	esac

	for file in cheat.dat event.dat hiscore.dat history.dat; do
		if [ -f "$HOME/.advance/$file" ]; then
			cp -f "$HOME/.advance/$file" "$COMMON_DIR/"
			rm -f "$HOME/.advance/$file"
		fi
	done
}
