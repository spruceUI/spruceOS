#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
#   GAME
#   EMU_JSON_PATH
#   PLATFORM
#   CORE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Provides:
#   run_dsperate

# DSperate is a from-source NDS emulator (spruceUI/DSperate-spruce), 64-bit
# only: its recompiler emits AArch64, so there is no 32-bit build worth
# offering. It sits alongside DraStic rather than replacing it.

DSPERATE_BIOS_DIR=/mnt/SDCARD/BIOS/nds

# DSperate needs a real DS BIOS pair and firmware. It cannot use the two files
# in Emu/NDS/system: those are DraStic's own replacements, not dumps (their
# md5s do not match the real BIOS), and there is no firmware image there at
# all. DSperate reads the real firmware for touchscreen calibration, the KEY1
# key table and the direct-boot path, so this is not something to work around.
dsperate_bios_missing() {
	_missing=""
	for _f in bios9.bin bios7.bin firmware.bin; do
		[ -f "$DSPERATE_BIOS_DIR/$_f" ] || _missing="$_missing $_f"
	done
	echo "$_missing"
}

display_dsperate_bios_message() {
	start_pyui_message_writer
	log_and_display_message "DSperate needs a DS BIOS dump.\nMissing from BIOS/nds:$1\nDumps are not included."
	sleep 6
	stop_pyui_message_writer
}

seed_dsperate_config() {
	mkdir -p /mnt/SDCARD/Saves/saves/dsperate /mnt/SDCARD/Saves/states/dsperate
	_cfg_dir="$XDG_CONFIG_HOME/dsperate"
	_cfg="$_cfg_dir/dsperate.ini"
	_cfg_a30="$_cfg_dir/a30.ini"
	_cfg_no_sticks="$_cfg_dir/no-sticks.ini"
	_cfg_one_stick="$_cfg_dir/one-stick.ini"
	mkdir -p "$_cfg_dir"
	if [ ! -f "$_cfg" ] && [ -f "$EMU_DIR/dsperate-configs/spruce.ini" ]; then
		cp -f "$EMU_DIR/dsperate-configs/spruce.ini" "$_cfg"
		log_message "DSperate: seeded config from spruce.ini"
	fi
	if [ ! -f "$_cfg_a30" ] && [ -f "$EMU_DIR/dsperate-configs/a30.ini" ]; then
		cp -f "$EMU_DIR/dsperate-configs/a30.ini" "$_cfg_a30"
		log_message "DSperate: seeded config from a30.ini"
	fi
	if [ ! -f "$_cfg_no_sticks" ] && [ -f "$EMU_DIR/dsperate-configs/no-sticks.ini" ]; then
		cp -f "$EMU_DIR/dsperate-configs/no-sticks.ini" "$_cfg_no_sticks"
		log_message "DSperate: seeded config from no-sticks.ini"
	fi
	if [ ! -f "$_cfg_one_stick" ] && [ -f "$EMU_DIR/dsperate-configs/one-stick.ini" ]; then
		cp -f "$EMU_DIR/dsperate-configs/one-stick.ini" "$_cfg_one_stick"
		log_message "DSperate: seeded config from one-stick.ini"
	fi
}

get_video_effect() {
	_setting="$(jq -r '.menuOptions.dsperateVideoEffect.selected // "None"' "${EMU_JSON_PATH:-/mnt/SDCARD/Emu/NDS/config.json}")"

    _override=$(jq -r --arg game "$GAME" ".menuOptions.dsperateVideoEffect.overrides[\$game]" "${EMU_JSON_PATH:-/mnt/SDCARD/Emu/NDS/config.json}")
    if [ -n "$_override" ] && [ "$_override" != "null" ]; then
        _setting="$_override"
    fi

	echo "$_setting"
}

# returns 0=true or 1=false; for now, no per-game override logic in place.
is_autoload_enabled() {
	_setting="$(jq -r '.menuOptions.dsperateAutoLoad.selected // "Enabled"' "${EMU_JSON_PATH:-/mnt/SDCARD/Emu/NDS/config.json}")"

    _override=$(jq -r --arg game "$GAME" ".menuOptions.dsperateAutoLoad.overrides[\$game]" "${EMU_JSON_PATH:-/mnt/SDCARD/Emu/NDS/config.json}")
    if [ -n "$_override" ] && [ "$_override" != "null" ]; then
        _setting="$_override"
    fi

	[ "$_setting" = "Enabled" ]
}

# The NDS header carries a four-character game code at offset 12, and DSperate
# names the auto slot after it, so the launcher has to read it the same way to
# know which file to resume from. Only the two containers DSperate itself
# opens are handled: a .7z has already been unpacked by prepare_dsperate_rom
# before this is called, and nothing on the card can read a .rar.
get_game_code() {
	case "$1" in
	*.nds | *.NDS)
		dd if="$1" bs=1 skip=12 count=4 2>/dev/null
		;;
	*.zip | *.ZIP)
		"$(get_python_path)" -c "
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        if name.lower().endswith('.nds'):
            sys.stdout.write(z.open(name).read(16)[12:16].decode('latin-1'))
            break
" "$1" 2>/dev/null
		;;
	esac
}

# Empty when the code cannot be read: a .rar, an archive with no .nds inside,
# or a header full of junk. The caller has to check, because falling back to a
# bare ".auto.dss" would be both a path DSperate never writes and one every
# game would share.
get_state_path() {
	_code="$(get_game_code "$1" | tr -dc 'A-Za-z0-9#_-')"
	[ -n "$_code" ] || return 0
	echo "/mnt/SDCARD/Saves/states/dsperate/${_code}.auto.dss"
}

# DSperate reads .nds and .zip itself (the vendored miniz in core/cart/zip.cpp),
# so .7z is the only container that needs unpacking. NDS extlist also offers
# .rar, which nothing on the card can open - 7zr is a 7z-only build.
#
# Unpacked to the card, not to mktemp's /tmp: /tmp is tmpfs here, and an NDS
# ROM is tens to hundreds of megabytes of RAM the emulator is about to want for
# itself.
#
# The unpacked file keeps the archive's own name because DSperate derives the
# battery save from the ROM's filename stem, not from the game code
# (save_path() in its main.cpp). Extract every game to a fixed "rom.nds" and
# they all share one .sav, which loses saves rather than just misplacing them.
DSPERATE_TMP_DIR="/mnt/SDCARD/spruce/tmp/dsperate"

prepare_dsperate_rom() {
	case "$1" in
	*.7z | *.7Z) ;;
	*) echo "$1"; return 0 ;;
	esac

	# A previous launch killed with -9 leaves its unpacked ROM behind.
	rm -rf "$DSPERATE_TMP_DIR"
	mkdir -p "$DSPERATE_TMP_DIR"

	_member="$(7zr l -slt "$1" 2>/dev/null | sed -n 's/^Path = //p' | grep -iE '\.nds$' | head -1)"
	if [ -z "$_member" ]; then
		log_message "DSperate: no .nds inside $(basename "$1")"
		return 1
	fi

	# Uncompressed size against what the card has free, both in KB. NF-2 is the
	# Available column counted from the right, so a wrapped df line still reads.
	_need_kb=$(( $(7zr l -slt "$1" 2>/dev/null | sed -n 's/^Size = //p' | awk '{s+=$1} END {print s+0}') / 1024 + 1 ))
	_free_kb="$(df -k "$DSPERATE_TMP_DIR" | awk 'END {print $(NF-2)}')"
	if [ "$_free_kb" -lt $((_need_kb + 16384)) ]; then
		log_message "DSperate: not enough card space to unpack $(basename "$1"): needs ${_need_kb}KB, ${_free_kb}KB free"
		return 1
	fi

	_stem="$(basename "$1")"
	_out="$DSPERATE_TMP_DIR/${_stem%.*}.nds"
	if ! 7zr e "$1" "$_member" -so > "$_out"; then
		log_message "DSperate: could not unpack $(basename "$1")"
		return 1
	fi
	log_message "DSperate: unpacked $(basename "$1") to the card"
	echo "$_out"
}

run_dsperate() {
	export HOME="$EMU_DIR"
	export XDG_CONFIG_HOME="/mnt/SDCARD/Saves"
	export LD_LIBRARY_PATH="$EMU_DIR/lib64:$LD_LIBRARY_PATH"

	_missing="$(dsperate_bios_missing)"
	if [ -n "$_missing" ]; then
		log_message "DSperate: missing BIOS:$_missing"
		mkdir -p "$DSPERATE_BIOS_DIR"
		display_dsperate_bios_message "$_missing"
		return 1
	fi

	seed_dsperate_config

	# DSperate opens Gamepads and Keyboards, but not joysticks so SDL needs to
	# be able to see them. DSperate also binds by SDL position (DS A = pad "b").
	export_sdl_gamecontroller_map positional

	if ! _rom="$(prepare_dsperate_rom "$ROM_FILE")"; then
		start_pyui_message_writer
		log_and_display_message "Could not unpack $(basename "$ROM_FILE")."
		sleep 4
		stop_pyui_message_writer
		return 1
	fi

	cd "$EMU_DIR"
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"

	# Speed, per-stage times and audio buffer depth, once a second. The buffer
	# depth is the one that matters: DSperate paces the emulator off the audio
	# queue, so a depth that oscillates means the pacing loop is the problem and
	# a steady one points at the resampler instead. Tied to verbose logging
	# because emu_log_file is /dev/null without it, so this would have nowhere
	# to go anyway.
	[ "$VERBOSE_EMU" = "1" ] && export DS_FPS=1

	# The BIOS paths are in spruce.ini too, but pass them anyway: they are what
	# dsperate_bios_missing just checked for, and a card upgraded from a config
	# seeded before spruce.ini existed has no [paths] block at all.
	set -- "$_rom" \
		--bios9 "$DSPERATE_BIOS_DIR/bios9.bin" \
		--bios7 "$DSPERATE_BIOS_DIR/bios7.bin" \
		--firmware "$DSPERATE_BIOS_DIR/firmware.bin" \
		--fullscreen

	_state="$(get_state_path "$_rom")"
	if [ -n "$_state" ] && [ -f "$_state" ] && is_autoload_enabled; then
		set -- "$@" --load-state "$_state"
	fi

	_video_effect="$(get_video_effect)"
	case "$_video_effect" in
		"None") ;;
		"Antialiasing") set -- "$@" --aa --seam blend ;;
		"Bilinear") set -- "$@" --linear ;;
		"Chunky Grid") set -- "$@" --chunky --lcd-grid 1 ;;
		"Extra Chunky") set -- "$@" --chunky --chunky-cell 8 ;;
	esac

	# The game switcher's thumbnail, written by DSperate itself with the auto
	# state (emu.autosave_png). The device's take_screenshot runs first in
	# the hold-Home path and this overwrites it a moment later, which is the
	# point: that grab reads the panel from outside and cannot see what the
	# emulator draws on a hardware scaler layer (the A30 got a jumble of the
	# frame at the wrong stride). PyUI uses the basename with no extension,
	# so we match that here too.
	_gs_dir="/mnt/SDCARD/Saves/states/.gameswitcher"
	_gs_name="$(basename "$ROM_FILE")"
	mkdir -p "$_gs_dir"
	set -- "$@" --autosave-png "$_gs_dir/${_gs_name%.*}.state.auto.png"

	if [ "$PLATFORM" = "A30" ]; then
		export DS_ROTATE=270
		./dsperate.a30 "$@" --config "/mnt/SDCARD/Saves/dsperate/a30.ini" > "$(emu_log_file)" 2>&1

	elif [ "$DEVICE_NUM_ANALOG_STICKS" = "0" ]; then
		./dsperate "$@" --config "/mnt/SDCARD/Saves/dsperate/no-sticks.ini" > "$(emu_log_file)" 2>&1

	elif [ "$DEVICE_NUM_ANALOG_STICKS" = "1" ]; then
		./dsperate "$@" --config "/mnt/SDCARD/Saves/dsperate/one-stick.ini" > "$(emu_log_file)" 2>&1

	else
		# let XDG_CONFIG_HOME or other XDG paths determine the config location
		./dsperate "$@" > "$(emu_log_file)" 2>&1
	fi

	rm -rf "$DSPERATE_TMP_DIR"
	sync
}
