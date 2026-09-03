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
    autoload_setting="$(jq -r '.menuOptions.dsperateAutoLoad.selected' "/mnt/SDCARD/Emu/NDS/config.json")"
    if [ "$autoload_setting" = "Enabled" ]; then
		return 0
	else
		return 1
	fi
}

get_game_code() {
	case "$1" in
		*.nds|*.NDS)
			dd if="$1" bs=1 skip=12 count=4 2>/dev/null
			;;
		*.zip|*.ZIP)
			unzip -p "$1" '*.nds' | dd bs=1 skip=12 count=4 2>/dev/null
			;;
	esac
	echo
}

get_state_path() {
	_code=$(get_game_code "$1")
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

	pin_to_dedicated_cores dsperate 3

	state_path="$(get_state_path "$ROM_FILE")"

	if is_autoload_enabled && [ -f "$state_path" ]; then
		./dsperate "$ROM_FILE" \
			--fullscreen \
			--load-state "$state_path" \
			> "$(emu_log_file)" 2>&1
	else
		./dsperate "$ROM_FILE" \
			--fullscreen \
			> "$(emu_log_file)" 2>&1
	fi

	sync
}
