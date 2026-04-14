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

run_mupen_standalone() {

	export HOME="$EMU_DIR/${MUPEN_DIR:-mupen64plus}"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	export XDG_CONFIG_HOME="$HOME"
	export XDG_DATA_HOME="$HOME"
	export LD_LIBRARY_PATH="$HOME:$LD_LIBRARY_PATH"
	cd "$HOME"

	# Calculate 4:3 canvas for the hacked rice patch
	G_WIDTH=$((DISPLAY_HEIGHT * 4 / 3))
	G_HEIGHT=$DISPLAY_HEIGHT

	# Read standalone settings (video plugin, frameskip, etc.)
	STANDALONE_SETTINGS="/mnt/SDCARD/Emu/N64/standalone_settings.json"
	if [ -f "$STANDALONE_SETTINGS" ]; then
		SA_PLUGIN=$(jq -r '.video_plugin // "rice"' "$STANDALONE_SETTINGS")
		SA_FRAMESKIP=$(jq -r '.frameskip // "0"' "$STANDALONE_SETTINGS")
		SA_CPU=$(jq -r '.cpu_emulator // "2"' "$STANDALONE_SETTINGS")
		SA_EXPANSION=$(jq -r '.expansion_pak // "1"' "$STANDALONE_SETTINGS")
	else
		SA_PLUGIN="rice"
		SA_FRAMESKIP="0"
		SA_CPU="2"
		SA_EXPANSION="1"
	fi

	# Map plugin name to .so filename
	case "$SA_PLUGIN" in
		rice) GFX_PLUGIN="mupen64plus-video-rice.so" ;;
		glide64mk2) GFX_PLUGIN="mupen64plus-video-glide64mk2.so" ;;
		gliden64) GFX_PLUGIN="mupen64plus-video-GLideN64.so" ;;
		*) GFX_PLUGIN="mupen64plus-video-rice.so" ;;
	esac

	if [ "$PLATFORM" = "A30" ]; then
		# A30: render at 480x360 (4:3 fitting in 480-wide portrait framebuffer)
		ARGS="--gfx $GFX_PLUGIN --resolution 480x360"
	elif [ "$SA_PLUGIN" = "gliden64" ]; then
		# GLideN64 has built-in 4:3 centering — give it full display resolution
		ARGS="--gfx $GFX_PLUGIN --resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} --set GLideN64[AspectRatio]=1"
	else
		# Rice/Glide64mk2: render at 4:3, offset viewport on widescreen
		ARGS="--gfx $GFX_PLUGIN --resolution ${G_WIDTH}x${G_HEIGHT} --set Video-Rice[ResolutionWidth]=$DISPLAY_WIDTH --set Video-Rice[ResolutionHeight]=$DISPLAY_HEIGHT"
		if [ "$DISPLAY_WIDTH" -gt "$G_WIDTH" ]; then
			export M64P_VIEWPORT_X=$(( (DISPLAY_WIDTH - G_WIDTH) / 2 ))
		fi
	fi

	# Apply standalone settings via --set
	if [ "$SA_FRAMESKIP" = "auto" ]; then
		ARGS="$ARGS --set Video-Rice[SkipFrame]=1 --set Video-Glide64mk2[autoframeskip]=1"
	elif [ "$SA_FRAMESKIP" != "0" ]; then
		ARGS="$ARGS --set Video-Rice[SkipFrame]=1 --set Video-Glide64mk2[maxframeskip]=$SA_FRAMESKIP"
	fi
	ARGS="$ARGS --set Core[R4300Emulator]=$SA_CPU"
	[ "$SA_EXPANSION" = "0" ] && ARGS="$ARGS --set Core[DisableExtraMem]=True"

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

	[ "$PLATFORM" = "Flip" ] && echo "-1" > /sys/class/miyooio_chr_dev/joy_type
	if [ "$PLATFORM" = "A30" ]; then
		export M64P_ROTATE=1
		# Input shim: grabs keyboard (event3), R2-hold for C-buttons, passthrough rest
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

	rm -rf "$TEMP_ROM"
}
