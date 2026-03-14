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
#   run_mpv

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
		ffplay -x $DISPLAY_WIDTH -y $DISPLAY_HEIGHT -fs -loglevel 24 -i "$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	fi

	kill -9 "$(pidof gptokeyb)"
}

run_mpv() {
	# pixel 2 only
	export HOME=$EMU_DIR
	cd $EMU_DIR

	INPUT_CONF="/tmp/mpv_input.conf"
	printf 'VOLUME_UP ignore\nVOLUME_DOWN ignore' > $INPUT_CONF

	/mnt/SDCARD/spruce/bin64/gptokeyb -k "mpv" -c "./bin64/mpv.gptk" &
	sleep 0.5

	/usr/bin/mpv --fs --geometry="640x480" --hwdec=drm --vo=sdl \
				 --input-conf=$INPUT_CONF --msg-level=all=warn \
				"$ROM_FILE" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1

	kill -9 "$(pidof gptokeyb)"
}