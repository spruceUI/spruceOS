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
		sed -i 's|^transform_screen 0$|transform_screen 135|' "$HOME/.lexaloffle/pico-8/config.txt"

	elif [ "$PLATFORM" = "MiyooMini" ]; then
		export SDL_VIDEODRIVER=mmiyoo
		export SDL_AUDIODRIVER=mmiyoo
		export EGL_VIDEODRIVER=mmiyoo
		export SDL_MMIYOO_DOUBLE_BUFFER=1
		PICO8_BINARY="pico8_dyn"
		killall audioserver
		cpuclock 1600
		sed -i 's|^transform_screen 135$|transform_screen 0|' "$HOME/.lexaloffle/pico-8/config.txt"

	else
		PICO8_BINARY="pico8_64"
		sed -i 's|^transform_screen 135$|transform_screen 0|' "$HOME/.lexaloffle/pico-8/config.txt"
	fi

	if [ "${GAME##*.}" = "splore" ]; then
		check_and_connect_wifi
		$PICO8_BINARY -splore -width $DISPLAY_WIDTH -height $DISPLAY_HEIGHT -root_path "/mnt/SDCARD/Roms/PICO8/" $SCALING > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	else
		$PICO8_BINARY -width $DISPLAY_WIDTH -height $DISPLAY_HEIGHT -scancodes -run "$ROM_FILE" $SCALING > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
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
		"Brick" | "SmartPro")
			export LD_LIBRARY_PATH="$HOME"/lib-trimui:$LD_LIBRARY_PATH
			;;
		"SmartProS")
			export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:"$HOME"/lib-trimui
			;;
		"Pixel2")
			export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH
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