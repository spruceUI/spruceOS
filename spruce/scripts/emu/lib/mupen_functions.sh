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

	# That assumes a panel at least as wide as 4:3, which every device had until
	# the RGB30: it is square at 720x720, so the canvas came out 960 wide and
	# 240px of the picture hung off the right edge. The centering branch below
	# cannot help - it only fires when the panel is WIDER than the canvas.
	#
	# Fit to width instead and shorten the canvas to keep 4:3. Provably a no-op
	# on every other device, where DISPLAY_HEIGHT*4/3 is already <= DISPLAY_WIDTH
	# (Brick/BrickPro 1024x768 -> 1024, SmartPro/S 1280x720 -> 960, Flip/Pixel2
	# 640x480 -> 640).
	if [ "$G_WIDTH" -gt "$DISPLAY_WIDTH" ]; then
		G_WIDTH=$DISPLAY_WIDTH
		G_HEIGHT=$((DISPLAY_WIDTH * 3 / 4))
	fi

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

# Anbernic RG XX (H700): the pad is read through the staged mali SDL2, whose
# raw joystick numbering is +3 over udev (A b3 ... MENU b11), with the
# stick-click keys interleaving the triggers per XX_PAD_LAYOUT. Three things
# make the fleet's N64 layout hold here:
#   - gptokeyb2 is not started: the mali SDL2 has no evdev keyboard path, so
#     its keystrokes never arrive. Every N64 button is a raw joystick binding
#     in the pad table instead (the positional map still goes to SDL for
#     anything that asks);
#   - mupen's own input-sdl plugin matches InputAutoCfg.ini by joystick name,
#     and the table is mupen's read-only asset, so it ships per pad layout
#     under xx-pad/ per platform (stickless models have L2 at b12, so
#     their "Z Trig" differs) and the platform's copy is put in place
#     before launch;
#   - the [CoreEvents] joypad hotkeys in the shared mupen64plus.cfg are
#     Xbox-360-numbered (J0B8 = guide) and cannot serve this pad, so the
#     same chords are passed as --set overrides in this pad's numbering:
#     MENU (b11) + START stop, + R1 save, + L1 load, + hat slot, + B reset,
#     + Y screenshot, + X pause, + A mute, + SELECT speed limiter.
# The --set overrides live in run_mupen_standalone, appended to the
# positional parameters after $ARGS is split, because "Joy Mapping Stop"
# carries spaces and cannot travel through a word-split string.
apply_xx_mupen_pad() {
	case "$PLATFORM" in
		"Anbernic"*) ;;
		*) return 0 ;;
	esac
	export_sdl_gamecontroller_map positional

	# InputAutoCfg.ini is a shipped default set, one file per platform;
	# nothing is computed here, the platform's file is copied over the live
	# table.
	src="$HOME/xx-pad/InputAutoCfg-$PLATFORM.ini"
	AC="$HOME/InputAutoCfg.ini"
	if [ -f "$src" ]; then
		cp -f "$src" "$AC"
	elif [ -f "$AC" ]; then
		# Fallback only: no shipped table for this platform, so fix up the
		# one trigger that moves. Not reached while xx-pad/ ships one per platform.
		log_message "xx mupen pad: no shipped InputAutoCfg for $PLATFORM, rewriting Z Trig as a fallback"
		case "$XX_PAD_LAYOUT" in
			nostick) ztrig="button(12)" ;;
			*)       ztrig="button(13)" ;;
		esac
		awk -v z="$ztrig" '
			/^\[/ { in_xx = ($0 == "[Linux: ANBERNIC-keys]") }
			in_xx && /^Z Trig = / { print "Z Trig = " z; next }
			{ print }
		' "$AC" > "$AC.tmp" && mv "$AC.tmp" "$AC"
	fi
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

		set -- $ARGS
		case "$PLATFORM" in
			"Anbernic"*)
				apply_xx_mupen_pad
				set -- "$@" \
					--set "CoreEvents[Joy Mapping Stop]=J0B11/B10" \
					--set "CoreEvents[Joy Mapping Save State]=J0B11/B8" \
					--set "CoreEvents[Joy Mapping Load State]=J0B11/B7" \
					--set "CoreEvents[Joy Mapping Increment Slot]=J0B11/H0V2" \
					--set "CoreEvents[Joy Mapping Reset]=J0B11/B4" \
					--set "CoreEvents[Joy Mapping Screenshot]=J0B11/B5" \
					--set "CoreEvents[Joy Mapping Pause]=J0B11/B6" \
					--set "CoreEvents[Joy Mapping Mute]=J0B11/B3" \
					--set "CoreEvents[Joy Mapping Speed Limiter Toggle]=J0B11/B9"
				;;
		esac
		case "$PLATFORM" in
			"A30")
				export M64P_ROTATE=1
				./a30_input_shim /dev/input/event3 &
				sleep 0.3
				;;
			"Anbernic"*)
				# No gptokeyb2: the mali SDL2 has no evdev keyboard path, so
				# its keystrokes never arrive. The pad table is all raw joystick.
				;;
			*)
				./gptokeyb2 "mupen64plus" -c "./defkeys.gptk" &
				sleep 0.3
				;;
		esac

		# Stickless XX: the N64 stick is axes 0/1, which have no stick behind
		# them there, so let the d-pad drive them for the run.
		_xx_dpad_swap 2
		./mupen64plus "$@" "$ROM_PATH" > $(emu_log_file) 2>&1
		_xx_dpad_swap 0

		case "$PLATFORM" in
			"A30") kill -9 $(pidof a30_input_shim) 2>/dev/null ;;
			"Anbernic"*) ;;
			*) kill -9 $(pidof gptokeyb2) ;;
		esac

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
