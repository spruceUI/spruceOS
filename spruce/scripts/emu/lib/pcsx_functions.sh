#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   PLATFORM
#   PCSX_BIN  (from platform .cfg)
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_pcsx_standalone

run_pcsx_standalone() {
	case "$PLATFORM" in
		"A30")
			PCSX_LIBDIR="$EMU_DIR/liba30"
			export PCSX_ROTATE=270
			export ALSA_NAME=none
			;;
		"MiyooMini") PCSX_LIBDIR="$EMU_DIR/libmini" ;;
		*)           PCSX_LIBDIR="$EMU_DIR/libs" ;;
	esac
	[ -d "$PCSX_LIBDIR" ] && export LD_LIBRARY_PATH="$PCSX_LIBDIR:$LD_LIBRARY_PATH"
	export HOME="$EMU_DIR"

	mkdir -p "$HOME/.pcsx/bios"
	mount --bind /mnt/SDCARD/BIOS "$HOME/.pcsx/bios"

	cd "$HOME"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh

	case "$PLATFORM" in
		"Anbernic"*) write_xx_pcsx_binds ;;
	esac

	"./${PCSX_BIN:-pcsx_64}" -cdfile "$ROM_FILE" -load 1 > $(emu_log_file) 2>&1

	umount "$HOME/.pcsx/bios" 2>/dev/null
}

# Anbernic RG XX (H700). pcsx_64 links SDL 1.2, whose evdev joystick probe
# insists on ABS_X/ABS_Y and this pad reports neither, so it falls back to the
# legacy joydev node: buttons in ascending evdev order (A 0, B 1, Y 2, X 3,
# L1 4, R1 5, SELECT 6, START 7, MENU 8, then L3/L2/R2/R3 as the layout has
# them, then the MENU tap pulse), sticks on the first axes, and the d-pad hat
# as the LAST two axes. libpicofe names a button 0xA0+index, and an axis
# 0xA0 + <number of buttons> + axis*2 (+1 for the positive half). The names
# therefore shift with the layout, so the section is written per launch from
# XX_PAD_LAYOUT rather than shipped.
#
# Layout matches the fleet's X360 section by position: Cross on the bottom
# button (B), Circle on A, Square on Y, Triangle on X; both sticks where they
# exist. Derived from the joydev tables measured on a CubeXX and RG SP, not
# yet run against pcsx_64 on the device.
write_xx_pcsx_binds() {
	cfg="$HOME/.pcsx/pcsx.cfg"
	[ -f "$cfg" ] || return 0

	case "$XX_PAD_LAYOUT" in
		nostick)
			# 12 buttons (A..R2 + pulse): L2 9, R2 10; axes RX RY RZ hat -> hat at 3/4
			nb=12; l2='\xA9'; r2='\xAA'; l3=''; r3=''; hx=3; hy=4; analog='bind_analog = 0
bind_analog = 1' ;;
		1stick)
			# 13 buttons: L3 9, L2 10, R2 11; axes Z RX RY RZ hat -> hat at 4/5
			nb=13; l2='\xAA'; r2='\xAB'; l3='\xA9'; r3=''; hx=4; hy=5; analog='bind_analog = 0
bind_analog = 1' ;;
		*)
			# 14 buttons: L3 9, L2 10, R2 11, R3 12; axes Z RX RY RZ hat -> hat at 4/5
			nb=14; l2='\xAA'; r2='\xAB'; l3='\xA9'; r3='\xAC'; hx=4; hy=5; analog='bind_analog = 0
bind_analog = 1
bind_analog = 2
bind_analog = 3' ;;
	esac
	# axis name = 0xA0 + nb + axis*2 (+1 positive)
	_ax() { printf '\\x%02X' $((0xA0 + nb + $1 * 2 + $2)); }

	# Drop any earlier ANBERNIC-keys section (everything from its binddev to
	# the next binddev), then append the fresh one.
	awk 'BEGIN{skip=0} /^binddev = /{skip = ($0 == "binddev = sdl:ANBERNIC-keys")} !skip{print}' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
	{
		printf '\nbinddev = sdl:ANBERNIC-keys\n'
		printf 'bind \\xA1 = player1 cross\nbind \\xA0 = player1 circle\nbind \\xA2 = player1 square\nbind \\xA3 = player1 triangle\n'
		printf 'bind \\xA4 = player1 l1\nbind \\xA5 = player1 r1\nbind \\xA6 = player1 select\nbind \\xA7 = player1 start\n'
		printf 'bind %s = player1 l2\nbind %s = player1 r2\n' "$l2" "$r2"
		[ -n "$l3" ] && printf 'bind %s = player1 l3\n' "$l3"
		[ -n "$r3" ] && printf 'bind %s = player1 r3\n' "$r3"
		printf 'bind %s = player1 left\nbind %s = player1 right\nbind %s = player1 up\nbind %s = player1 down\n' \
			"$(_ax $hx 0)" "$(_ax $hx 1)" "$(_ax $hy 0)" "$(_ax $hy 1)"
		printf '%s\n' "$analog"
	} >> "$cfg"
}
