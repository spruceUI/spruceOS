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

run_openbor() {
	export HOME=$EMU_DIR
	cd $HOME
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
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
}
