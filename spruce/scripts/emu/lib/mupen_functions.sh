#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   DISPLAY_WIDTH
#   DISPLAY_HEIGHT
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_mupen_standalone

# Read a value from mupen64plus.cfg by [section] and key.
# Usage: get_cfg_value section key default
get_cfg_value() {
	local result
	result=$(awk -v sec="$1" -v key="$2" '
		/^\[/ { in_sec = (index($0, "[" sec "]") > 0) }
		in_sec && index($0, key) == 1 && index($0, "=") > 0 {
			sub(/^[^=]*= */, "")
			sub(/ *$/, "")
			print
			exit
		}
	' "$HOME/.config/mupen64plus/mupen64plus.cfg" 2>/dev/null)
	echo "${result:-$3}"
}

# Build launch args from current config. Called before each launch so
# a restart picks up any settings changed via the overlay menu.
build_mupen_args() {
	# Calculate 4:3 canvas for the Rice/Glide64mk2 viewport centering patch
	G_WIDTH=$((DISPLAY_HEIGHT * 4 / 3))
	G_HEIGHT=$DISPLAY_HEIGHT

	# Read video plugin from overlay config (written to [SpruceOS] section)
	# Values: 0=GLideN64, 1=Rice, 2=Glide64mk2
	SA_PLUGIN_NUM=$(get_cfg_value SpruceOS VideoPlugin 1)
	case "$SA_PLUGIN_NUM" in
		0) SA_PLUGIN="gliden64" ;;
		2) SA_PLUGIN="glide64mk2" ;;
		*) SA_PLUGIN="rice" ;;
	esac

	# Map plugin name to .so filename
	case "$SA_PLUGIN" in
		rice) GFX_PLUGIN="mupen64plus-video-rice.so" ;;
		glide64mk2) GFX_PLUGIN="mupen64plus-video-glide64mk2.so" ;;
		gliden64) GFX_PLUGIN="mupen64plus-video-GLideN64.so" ;;
		*) GFX_PLUGIN="mupen64plus-video-rice.so" ;;
	esac

	if [ "$PLATFORM" = "A30" ]; then
		ARGS="--gfx $GFX_PLUGIN --resolution 480x360"
	elif [ "$SA_PLUGIN" = "gliden64" ]; then
		ARGS="--gfx $GFX_PLUGIN --resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} --set GLideN64[AspectRatio]=1"
	else
		ARGS="--gfx $GFX_PLUGIN --resolution ${G_WIDTH}x${G_HEIGHT} --set Video-Rice[ResolutionWidth]=$DISPLAY_WIDTH --set Video-Rice[ResolutionHeight]=$DISPLAY_HEIGHT"
		if [ "$DISPLAY_WIDTH" -gt "$G_WIDTH" ]; then
			export M64P_VIEWPORT_X=$(( (DISPLAY_WIDTH - G_WIDTH) / 2 ))
		fi
	fi

	export EMU_VIDEO_PLUGIN="$SA_PLUGIN"
}

run_mupen_standalone() {

	export HOME="$EMU_DIR/${MUPEN_DIR:-mupen64plus}"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	export XDG_CONFIG_HOME="$HOME"
	export XDG_DATA_HOME="$HOME"
	export LD_LIBRARY_PATH="$HOME:$LD_LIBRARY_PATH"
	cd "$HOME"

	case "$ROM_FILE" in
	*.n64 | *.v64 | *.z64)
		ROM_PATH="$ROM_FILE"
		;;
	*.zip)
		TEMP_ROM=$(mktemp -d)
		"$(get_python_path)" -c "
import zipfile, sys
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
" "$ROM_FILE" "$TEMP_ROM"
		ROM_PATH="$(find "$TEMP_ROM" -type f | head -1)"
		;;
	*.7z)
		TEMP_ROM=$(mktemp)
		ROM_PATH="$TEMP_ROM"
		7zr e "$ROM_FILE" -so >"$TEMP_ROM"
		;;
	esac

	export M64P_AUTOLOAD=1
	export EMU_OVERLAY_ROMFILE="$ROM_FILE"

	rm -f /tmp/mupen_restart
	[ "$PLATFORM" = "Flip" ] && echo "-1" > /sys/class/miyooio_chr_dev/joy_type

	while true; do
		build_mupen_args

		if [ "$PLATFORM" = "A30" ]; then
			export M64P_ROTATE=1
			./a30_input_shim /dev/input/event3 &
			sleep 0.3
		else
			./gptokeyb2 "mupen64plus" -c "./defkeys.gptk" &
			sleep 0.3
		fi

		./mupen64plus $ARGS "$ROM_PATH" > $(emu_log_file) 2>&1

		if [ "$PLATFORM" = "A30" ]; then
			kill -9 $(pidof a30_input_shim) 2>/dev/null
		else
			kill -9 $(pidof gptokeyb2)
		fi

		# Restart loop: overlay writes /tmp/mupen_restart when user selects Restart
		if [ -f /tmp/mupen_restart ]; then
			rm -f /tmp/mupen_restart
			log_message "mupen_functions.sh: Restarting mupen64plus"
		else
			break
		fi
	done

	rm -rf "$TEMP_ROM"
}
