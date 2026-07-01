#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   GAME
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_openbor
#   move_screenshots_if_present

SS_DIR="/mnt/SDCARD/Saves/screenshots/OpenBOR"

move_screenshots_if_present() {
	if [ -n "$(ls -A $HOME/ScreenShots/*.png 2>/dev/null)" ]; then
		mv $HOME/ScreenShots/*.png "$SS_DIR/" 2>/dev/null
	fi
}

run_openbor() {
	export HOME=/mnt/SDCARD/Saves/saves/OPENBOR
	mkdir -p $HOME
	cd $HOME
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"

	mkdir -p "$HOME/ScreenShots"
	mkdir -p "$SS_DIR"

	move_screenshots_if_present
	mount --bind "$SS_DIR" "$HOME/ScreenShots"

	if [ "$PLATFORM" = "Flip" ]; then

		if [ "$GAME" = "Final Fight LNS.pak" ]; then
			export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64mod
			$EMU_DIR/OpenBOR_64_mod "$ROM_FILE" > $(emu_log_file) 2>&1
		else
			export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME
			$EMU_DIR/OpenBOR_Flip "$ROM_FILE" > $(emu_log_file) 2>&1
		fi

	elif [ "$PLATFORM" = "A30" ]; then

		export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib
		killall -q -USR2 joystickinput
		if [ "$GAME" = "Final Fight LNS.pak" ]; then
			$EMU_DIR/OpenBOR_mod "$ROM_FILE" > $(emu_log_file) 2>&1
		else
			$EMU_DIR/OpenBOR_new "$ROM_FILE" > $(emu_log_file) 2>&1
		fi
		killall -q -USR1 joystickinput

	else # TrimUI Brick, SmartPro, or SmartProS

		if [ "$GAME" = "Final Fight LNS.pak" ]; then
			if [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "Brick" ]; then
				export SDL_VIDEODRIVER=mali
				"/mnt/SDCARD/Emu/PSP/setalpha" 0
				export LD_LIBRARY_PATH=$EMU_DIR/lib64mod:$LD_LIBRARY_PATH
				$EMU_DIR/OpenBOR_64_mod "$ROM_FILE" > $(emu_log_file) 2>&1
			else
				export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64mod
				$EMU_DIR/OpenBOR_64_mod "$ROM_FILE" > $(emu_log_file) 2>&1
			fi
		else
			export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
			$EMU_DIR/OpenBOR_TrimUI "$ROM_FILE" > $(emu_log_file) 2>&1
		fi

	fi
	sync

	umount "$HOME/ScreenShots"
}
