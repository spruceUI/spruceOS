#!/bin/sh

# Requires globals: EMU_DIR, ROM_FILE, PLATFORM, CORE, LOG_DIR
# Provides: run_advmame

run_advmame() {
	ADV_DIR=/mnt/SDCARD/Saves/saves/advmame/.advance
	mkdir -p "$ADV_DIR"
	for file in cheat.dat event.dat hiscore.dat history.dat; do
	if [ -f "$EMU_DIR/$file" ]; then
		cp "$EMU_DIR/$file" "$ADV_DIR/" && rm "$EMU_DIR/$file"
	fi
	done
	DEF_RC=$EMU_DIR/advmame-${PLATFORM}.rc
	RC_FILE=${ADV_DIR}/advmame-${PLATFORM}.rc

	if [ ! -f "$RC_FILE" ] && [ -f "$DEF_RC" ]; then
		cp "$DEF_RC" "$RC_FILE"
	fi

	export HOME="/mnt/SDCARD/Saves/saves/advmame"
	ADVMAME_LOG="${LOG_DIR}/${CORE}-${PLATFORM}.log"
	ROM_DIR=$(dirname "$ROM_FILE")

	cd "$EMU_DIR"
	case "$PLATFORM" in
		"SmartPro"|"Brick")
			[ -f "$EMU_DIR/advmame.log" ] && rm "$EMU_DIR/advmame.log"
			export LD_LIBRARY_PATH="/mnt/SDCARD/Emu/ARCADE/lib:/mnt/SDCARD/Persistent/portmaster/PortMaster:$LD_LIBRARY_PATH"
			export SDL_GAMECONTROLLERCONFIG="/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
			./fb_disable_transparency
			/mnt/SDCARD/Persistent/portmaster/PortMaster/gptokeyb2 $EMU_DIR/advmame -c "$EMU_DIR/advmame.ini" &
			HOME=$HOME $EMU_DIR/advmame -cfg $RC_FILE -dir_rom "$ROM_DIR" "${GAME%.*}" -log
			[ -f "$EMU_DIR/advmame.log" ] && cp "$EMU_DIR/advmame.log" "$ADVMAME_LOG"
			kill -9 $(pidof gptokeyb2)
			;;
		"SmartProS"|"Flip")
			[ -f "$EMU_DIR/advmame.log" ] && rm "$EMU_DIR/advmame.log"
			export LD_LIBRARY_PATH="/mnt/SDCARD/Emu/ARCADE/lib:/mnt/SDCARD/Persistent/portmaster/PortMaster:$LD_LIBRARY_PATH"
			export SDL_GAMECONTROLLERCONFIG="/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
			/mnt/SDCARD/Persistent/portmaster/PortMaster/gptokeyb2 $EMU_DIR/advmame -c "$EMU_DIR/advmame.ini" &
			HOME=$HOME $EMU_DIR/advmame -cfg $RC_FILE -dir_rom "$ROM_DIR" "${GAME%.*}" -log
			[ -f "$EMU_DIR/advmame.log" ] && cp "$EMU_DIR/advmame.log" "$ADVMAME_LOG"
			kill -9 $(pidof gptokeyb2)
			;;
	esac
}