#!/bin/sh

# Requires globals:
#   EMU_DIR
#   ROM_FILE
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
	[ -f "$_cfg" ] && return 0
	mkdir -p "$_cfg_dir"
	if [ -f "$EMU_DIR/dsperate-configs/spruce.ini" ]; then
		cp -f "$EMU_DIR/dsperate-configs/spruce.ini" "$_cfg"
		log_message "DSperate: seeded config from spruce.ini"
	fi
}

# returns 0=true or 1=false; for now, no per-game override logic in place.
is_autoload_enabled() {
	_setting="$(jq -r '.menuOptions.dsperateAutoLoad.selected // "Enabled"' "${EMU_JSON_PATH:-/mnt/SDCARD/Emu/NDS/config.json}")"
	[ "$_setting" = "Enabled" ]
}

# The NDS header carries a four-character game code at offset 12, and DSperate
# names the auto slot after it, so the launcher has to read it the same way to
# know which file to resume from. 7zr cannot open a .rar and neither can
# python's zipfile, so those come back empty rather than wrong.
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
	*.7z | *.7Z)
		7zr e "$1" -so 2>/dev/null | dd bs=1 skip=12 count=4 2>/dev/null
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
	set -- "$ROM_FILE" \
		--bios9 "$DSPERATE_BIOS_DIR/bios9.bin" \
		--bios7 "$DSPERATE_BIOS_DIR/bios7.bin" \
		--firmware "$DSPERATE_BIOS_DIR/firmware.bin" \
		--fullscreen

	_state="$(get_state_path "$ROM_FILE")"
	if [ -n "$_state" ] && [ -f "$_state" ] && is_autoload_enabled; then
		set -- "$@" --load-state "$_state"
	fi

	./dsperate "$@" > "$(emu_log_file)" 2>&1

	sync
}
