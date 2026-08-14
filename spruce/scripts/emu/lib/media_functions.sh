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
#   run_gvu
#   run_ffplay
#   run_mpv

run_gvu() {
	export HOME="$EMU_DIR"
	cd "$EMU_DIR"

	# GVU uses its own isolated lib dirs to avoid conflicts with ffplay
	if [ "$PLATFORM" = "A30" ]; then
		GVU_BIN="$EMU_DIR/bin32/gvu"
		export LD_LIBRARY_PATH="$EMU_DIR/gvu_lib32_a30:$EMU_DIR/gvu_lib32:$LD_LIBRARY_PATH"
	elif [ "$PLATFORM_ARCHITECTURE" = "aarch64" ]; then
		GVU_BIN="$EMU_DIR/bin64/gvu"
		export LD_LIBRARY_PATH="$EMU_DIR/gvu_lib64:$LD_LIBRARY_PATH"
	else
		GVU_BIN="$EMU_DIR/bin32/gvu"
		export LD_LIBRARY_PATH="$EMU_DIR/gvu_lib32:$LD_LIBRARY_PATH"
	fi

	export SDL_VIDEODRIVER=dummy
	export GVU_PLATFORM="$PLATFORM"
	export GVU_DISPLAY_W="$DISPLAY_WIDTH"
	export GVU_DISPLAY_H="$DISPLAY_HEIGHT"
	export GVU_DISPLAY_ROTATION="$DISPLAY_ROTATION"
	export GVU_INPUT_DEV="$EVENT_PATH_READ_INPUTS_SPRUCE"
	export GVU_PYTHON="$DEVICE_PYTHON3_PATH"
	export GVU_CACERT_PATH="$EMU_DIR/resources/cacert.pem"

	# Miyoo Mini family: display is physically upside-down (spruceOS reports rot=0)
	if [ "$PLATFORM" = "MiyooMini" ]; then
		export GVU_DISPLAY_ROTATION=180
		# Detect V4 (Mini Flip) by fb0 resolution
		if grep -q "752x560p" /sys/class/graphics/fb0/modes 2>/dev/null; then
			export GVU_DISPLAY_W=752
			export GVU_DISPLAY_H=560
			export LD_PRELOAD="/customer/lib/libpadsp.so"
			export SDL_AUDIODRIVER=dsp
		else
			# V2/V3/Plus: libpadsp.so crashes on these — run silent
			export SDL_AUDIODRIVER=dummy
		fi
	fi

	if [ "$OPEN_GVU_BROWSER" = "true" ]; then
		"$GVU_BIN" > $(emu_log_file) 2>&1
	else
		"$GVU_BIN" "$ROM_FILE" > $(emu_log_file) 2>&1
	fi
}

run_ffplay() {
	export HOME=$EMU_DIR
	cd $EMU_DIR
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	if [ "$PLATFORM" = "A30" ]; then
		export PATH="$EMU_DIR"/bin32:"$PATH"
		export LD_LIBRARY_PATH="$EMU_DIR"/lib32:/usr/miyoo/lib:/usr/lib:"$LD_LIBRARY_PATH"
		ffplay -vf transpose=2 -fs -i "$ROM_FILE" > $(emu_log_file) 2>&1
	else
		export PATH="$EMU_DIR"/bin64:"$PATH"
		export LD_LIBRARY_PATH="$LD_LIBRARY_PATH":"$EMU_DIR"/lib64
		/mnt/SDCARD/spruce/bin64/gptokeyb -k "ffplay" -c "./bin64/ffplay.gptk" &
		sleep 1
		ffplay -x $DISPLAY_WIDTH -y $DISPLAY_HEIGHT -fs -loglevel 24 -i "$ROM_FILE" > $(emu_log_file) 2>&1
	fi

	kill -9 "$(pidof gptokeyb)"
}

set_hw_vo() {
	# wlshm: software decoding
	# dmabuf-wayland: hardware decoding

	FILE_INFO=$(ffprobe -v quiet -print_format csv -select_streams v:0 -show_entries stream=pix_fmt,codec_name $1)
	CODEC=$(echo $FILE_INFO | cut -d"," -f2)
	FORMAT=$(echo $FILE_INFO | cut -d"," -f3)

	# 10/12 bit pixel format
	case "$FORMAT" in
		*10le|*12le|*16le)
			echo "wlshm"
			return
			;;
	esac

	# Supported codecs
	case "$CODEC" in
		h264|hevc)
			echo "dmabuf-wayland"
			return
			;;
		*)
			echo "wlshm"
			return
			;;
	esac
}

run_mpv() {
	# pixel 2 only
	export HOME=$EMU_DIR
	cd $EMU_DIR

	VO=$(set_hw_vo "$ROM_FILE")
	log_message "run_mpv: Using $VO"

	INPUT_CONF="/tmp/mpv_input.conf"
	printf 'VOLUME_UP ignore\nVOLUME_DOWN ignore' > $INPUT_CONF

	gptokeyb -k "mpv" -c "./mpv.gptk" &
	sleep 0.5

	/usr/bin/mpv --profile=fast --fs --geometry="640x480" --hwdec=rkmpp \
				 --vo=$VO --swapchain-depth=8 \
				 --input-conf=$INPUT_CONF --msg-level=all=warn \
				"$ROM_FILE" > $(emu_log_file) 2>&1

	kill -9 "$(pidof gptokeyb)"
}