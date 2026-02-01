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

	export HOME="$EMU_DIR/mupen64plus"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	export XDG_CONFIG_HOME="$HOME"
	export XDG_DATA_HOME="$HOME"
	export LD_LIBRARY_PATH="$HOME:$LD_LIBRARY_PATH"
	cd "$HOME"

	sed -i "s|^ScreenWidth *=.*|ScreenWidth = $DISPLAY_WIDTH|" "$HOME/.config/mupen64plus/mupen64plus.cfg"
	sed -i "s|^ScreenHeight *=.*|ScreenHeight = $DISPLAY_HEIGHT|" "$HOME/.config/mupen64plus/mupen64plus.cfg"

	case "$ROM_FILE" in
	*.n64 | *.v64 | *.z64)
		ROM_PATH="$ROM_FILE"
		;;
	*.zip | *.7z)
		TEMP_ROM=$(mktemp)
		ROM_PATH="$TEMP_ROM"
		7zr e "$ROM_FILE" -so >"$TEMP_ROM"
		;;
	esac

	[ "$PLATFORM" = "Flip" ] && echo "-1" > /sys/class/miyooio_chr_dev/joy_type
	./gptokeyb2 "mupen64plus" -c "./defkeys.gptk" &
	sleep 0.3
	./mupen64plus "$ROM_PATH" > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	kill -9 $(pidof gptokeyb2)

	rm -f "$TEMP_ROM"
}
