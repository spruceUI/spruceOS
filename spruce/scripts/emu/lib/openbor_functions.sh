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
	export HOME=$EMU_DIR
	cd $HOME
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"

	mkdir -p "$HOME/ScreenShots"
	mkdir -p "$SS_DIR"

	move_screenshots_if_present
	mount --bind "$SS_DIR" "$HOME/ScreenShots"

	if [ "$PLATFORM" = "Flip" ]; then

		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME
		./OpenBOR_Flip "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1

	elif [ "$PLATFORM" = "A30" ]; then

		export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib
		killall -q -USR2 joystickinput
		if [ "$GAME" = "Final Fight LNS.pak" ]; then
			./OpenBOR_mod "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
		else
			./OpenBOR_new "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
		fi
		killall -q -USR1 joystickinput

	else # TrimUI Brick, SmartPro, or SmartProS

		export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
		./OpenBOR_TrimUI "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	fi
	sync

	umount "$HOME/ScreenShots"
}
