#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   GAME
#   PLATFORM
#   EMU_JSON_PATH
#   DISPLAY_WIDTH
#   DISPLAY_HEIGHT
#   DISPLAY_ROTATION
#   PATH
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Requires functions:
#   check_and_connect_wifi
#
# Provides:
#   run_pico8
#   load_pico8_control_profile

run_pico8() {
    # send signal USR2 to joystickinput to switch to KEYBOARD MODE
	# this allows joystick to be used as DPAD in MainUI
	killall -q -USR2 joystickinput

	export HOME="$EMU_DIR"
	export PATH="$PATH:/mnt/SDCARD/BIOS"

	STRETCH="$(jq -r '.menuOptions.Stretch.selected' "$EMU_JSON_PATH")"
	if [ "$STRETCH" = "True" ]; then
		case "$DISPLAY_ROTATION" in
			"90"|"270") SCALING="-draw_rect 0,0,$DISPLAY_HEIGHT,$DISPLAY_WIDTH" ;; # handle A30's rotated screen
			"0"|"180")  SCALING="-draw_rect 0,0,$DISPLAY_WIDTH,$DISPLAY_HEIGHT" ;;
		esac
	else
		SCALING=""
	fi

	cd "$HOME"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh

	if [ "$PLATFORM" = "A30" ]; then
		export SDL_VIDEODRIVER=mali
		export SDL_JOYSTICKDRIVER=a30
		PICO8_BINARY="pico8_dyn"
		sed 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"
		sed 's/^button_keys.*/button_keys 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0/' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"

	elif [ "$PLATFORM" = "MiyooMini" ]; then
		export SDL_VIDEODRIVER=mmiyoo
		export SDL_AUDIODRIVER=mmiyoo
		export EGL_VIDEODRIVER=mmiyoo
		export SDL_MMIYOO_DOUBLE_BUFFER=1
		PICO8_BINARY="pico8_dyn"
		killall audioserver
		cpuclock 1600
		sed 's|^transform_screen 135$|transform_screen 0|' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"
		sed 's/^button_keys.*/button_keys 0 0 0 0 44 224 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0/' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"

	elif [ "$PLATFORM" = "Pixel2" ]; then
		enable_dpad_to_mouse
		PICO8_BINARY="pico8_64"
		sed 's|^transform_screen 135$|transform_screen 0|' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"
		sed 's/^button_keys.*/button_keys 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0/' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"

	elif [ "${PLATFORM#Anbernic}" != "$PLATFORM" ]; then
		PICO8_BINARY="pico8_64"

		if [ -n "$SPRUCE_BASEOS" ]; then
			# dll-mali's SDL2 lists only "mali dummy offscreen", so naming mali
			# saves a probe and stops a future SDL2 picking something else.
			export SDL_VIDEODRIVER=mali

			# PICO-8 asks SDL_Init for the sensor subsystem, which dll-mali is
			# not built with, and SDL_Init is all-or-nothing - so it dies with
			# "FATAL ERROR: Unable to initialize SDL" before drawing anything.
			# Probed subsystem by subsystem on a CubeXX: TIMER, AUDIO, VIDEO,
			# JOYSTICK, HAPTIC, GAMECONTROLLER and EVENTS all initialise and
			# only SENSOR fails, so masking that one bit is the whole fix. The
			# shim does exactly that and nothing else; source sits beside it in
			# Emu/PICO8/src.
			#
			# The alternative was the stock Anbernic SDL2, which does have
			# sensors - but it finds zero joysticks under BaseOS with udev on,
			# with udev disabled, and with SDL_JOYSTICK_DEVICE naming the node.
			# dll-mali finds the pad because it carries NextUI's H700 joystick
			# classification patch, which exists because these pads report no
			# ABS_X/ABS_Y for stock heuristics to latch onto.
			[ -f "$HOME/lib-h700/libsdl_sensor_shim.so" ] && \
				export LD_PRELOAD="$HOME/lib-h700/libsdl_sensor_shim.so${LD_PRELOAD:+:$LD_PRELOAD}"

			# None of the shipped sdl_controllers.* profiles cover
			# ANBERNIC-keys, so without this PICO-8 would see the pad but have
			# no GameController mapping for it. Same handoff ppsspp_functions.sh
			# does: AnbernicXXCommon.cfg picks the map by BASEOS_TARGET.
			[ -n "$SDL_GAMECONTROLLER_MAP" ] && export SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLER_MAP"
		fi

		# The RG28XX mounts its panel turned, exactly like the A30 - both report
		# DISPLAY_ROTATION 270 with the same 640x480 geometry - so it needs the
		# same transform. Keyed on the rotation rather than the model so the rest
		# of the line, which is all 0, keeps the upright setting.
		if [ "$DISPLAY_ROTATION" = "270" ]; then
			sed 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"
		else
			sed 's|^transform_screen 135$|transform_screen 0|' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"
		fi
		sed 's/^button_keys.*/button_keys 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0/' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"

	else
		PICO8_BINARY="pico8_64"
		sed 's|^transform_screen 135$|transform_screen 0|' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"
		sed 's/^button_keys.*/button_keys 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0/' "$HOME/.lexaloffle/pico-8/config.txt" > "$HOME/.lexaloffle/pico-8/config.txt.tmp" && mv "$HOME/.lexaloffle/pico-8/config.txt.tmp" "$HOME/.lexaloffle/pico-8/config.txt"
	fi

	if [ "${GAME##*.}" = "splore" ]; then
		check_and_connect_wifi
		$PICO8_BINARY -splore -width $DISPLAY_WIDTH -height $DISPLAY_HEIGHT -root_path "/mnt/SDCARD/Roms/PICO8/" $SCALING > $(emu_log_file) 2>&1
	else
		$PICO8_BINARY -width $DISPLAY_WIDTH -height $DISPLAY_HEIGHT -scancodes -run "$ROM_FILE" $SCALING > $(emu_log_file) 2>&1
	fi
	sync

	# send signal USR1 to joystickinput to switch to ANALOG MODE
	killall -q -USR1 joystickinput
}

load_pico8_control_profile() {
	export HOME="$EMU_DIR"
	P8_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"
	CONTROL_PROFILE="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	STEWARD_MODE="$(jq -r '.menuOptions.stewardMode.selected' "$EMU_JSON_PATH")"

	case "$PLATFORM" in
		"A30")
			if [ "$STEWARD_MODE" = "On - A-ⓧ B-ⓞ X-Esc SELECT-Mouse" ]; then
				export LD_LIBRARY_PATH="$HOME"/lib-stew:$LD_LIBRARY_PATH
			else
				export LD_LIBRARY_PATH="$HOME"/lib-cine:$LD_LIBRARY_PATH
			fi
			;;
		"Flip")
			export LD_LIBRARY_PATH="$HOME"/lib-Flip:$LD_LIBRARY_PATH
			;;
		"MiyooMini")
			export LD_LIBRARY_PATH="$HOME"/lib-MiyooMini:$LD_LIBRARY_PATH
			;;
		"Brick"* | "SmartPro")
			export LD_LIBRARY_PATH="$HOME"/lib-trimui:$LD_LIBRARY_PATH
			;;
		"SmartProS")
			export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:"$HOME"/lib-trimui
			;;
		"Pixel2")
			export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH
			;;
		"Anbernic"*)
			# Nothing to add. Under BaseOS the SDL2 PICO-8 needs is the
			# mali-fbdev build in dll-mali, which AnbernicXXCommon.cfg already
			# has on LD_LIBRARY_PATH; run_pico8 preloads a shim so its missing
			# sensor subsystem does not abort startup. On stock the system SDL2
			# is used, as before.
			;;
	esac

	case "$CONTROL_PROFILE" in
		"Doubled - A-ⓧ B-ⓞ Y-ⓧ X-ⓞ")	cp -f "$P8_DIR/sdl_controllers.facebuttons" "$P8_DIR/sdl_controllers.txt" ;;
		"One-hand - A-ⓧ B-ⓞ L1-ⓧ L2-ⓞ")	cp -f "$P8_DIR/sdl_controllers.onehand" 	"$P8_DIR/sdl_controllers.txt" ;;
		"Racing - A-ⓧ B-ⓞ L1-ⓧ R1-ⓞ")	cp -f "$P8_DIR/sdl_controllers.racing" 		"$P8_DIR/sdl_controllers.txt" ;;
		"Doubled II - B-ⓧ A-ⓞ X-ⓧ Y-ⓞ") cp -f "$P8_DIR/sdl_controllers.facebuttons_reverse" "$P8_DIR/sdl_controllers.txt" ;;
		"One-hand II - B-ⓧ A-ⓞ L2-ⓧ L1-ⓞ") cp -f "$P8_DIR/sdl_controllers.onehand_reverse"	"$P8_DIR/sdl_controllers.txt" ;;
		"Racing II - B-ⓧ A-ⓞ R1-ⓧ L1-ⓞ") cp -f "$P8_DIR/sdl_controllers.racing_reverse" 	"$P8_DIR/sdl_controllers.txt" ;;
	esac
}