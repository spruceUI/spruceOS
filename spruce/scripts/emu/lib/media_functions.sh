#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   DISPLAY_WIDTH
#   DISPLAY_HEIGHT
#   LD_LIBRARY_PATH
#   PATH
#   LOG_DIR
#
# Provides:
#   run_ffplay

run_ffplay() {
	export HOME=$EMU_DIR
	cd $EMU_DIR
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	if [ "$PLATFORM" = "A30" ]; then
		export PATH="$EMU_DIR"/bin32:"$PATH"
		export LD_LIBRARY_PATH="$EMU_DIR"/lib32:/usr/miyoo/lib:/usr/lib:"$LD_LIBRARY_PATH"
		ffplay -vf transpose=2 -fs -i "$ROM_FILE" > ffplay.log 2>&1
	else
		export PATH="$EMU_DIR"/bin64:"$PATH"
		export LD_LIBRARY_PATH="$LD_LIBRARY_PATH":"$EMU_DIR"/lib64
		/mnt/SDCARD/spruce/bin64/gptokeyb -k "ffplay" -c "./bin64/ffplay.gptk" &
		sleep 1
		ffplay -x $DISPLAY_WIDTH -y $DISPLAY_HEIGHT -fs -i "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	fi
}
