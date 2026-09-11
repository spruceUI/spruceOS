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



. /mnt/SDCARD/spruce/scripts/emu/lib/rac_functions.sh

seed_dsperate_config() {
	mkdir -p /mnt/SDCARD/Saves/saves/dsperate /mnt/SDCARD/Saves/states/dsperate
	_cfg_dir="$XDG_CONFIG_HOME/dsperate"
	_cfg_a30="$_cfg_dir/a30.ini"
	_cfg_no_sticks="$_cfg_dir/no-sticks.ini"
	_cfg_one_stick="$_cfg_dir/one-stick.ini"
	_cfg_two_sticks="$_cfg_dir/two-sticks.ini"

	mkdir -p "$_cfg_dir"
	if [ ! -f "$_cfg_two_sticks" ] && [ -f "$EMU_DIR/dsperate-configs/two-sticks.ini" ]; then
		cp -f "$EMU_DIR/dsperate-configs/two-sticks.ini" "$_cfg_two_sticks"
		log_message "DSperate: seeded config from two-sticks.ini"
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
	for _f in "$_cfg_a30" "$_cfg_no_sticks" "$_cfg_one_stick" "$_cfg_two_sticks"; do
		[ -f "$_f" ] && ! grep -q '^\[cheevos\]' "$_f" && printf '\n[cheevos]\nenabled = true\n' >> "$_f"
	done
}

# Hand DSperate the spruce RetroAchievements sign-in as a username + token
# file it only reads (DS_CHEEVOS_CFW_CONFIG); its own in-menu sign-in wins.
prepare_dsperate_cheevos() {
	_cfw="/mnt/SDCARD/Saves/spruce/cheevos.cfg"
	rac_mode="$(get_config_value '.menuOptions."RetroAchievements Settings".modeToggle.selected' "Manual")"
	rac_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
	case "$rac_mode" in
		Softcore|Hardcore) [ -n "$rac_user" ] || { rm -f "$_cfw"; return 0; } ;;
		*) rm -f "$_cfw"; return 0 ;;
	esac
	if ! grep -qx "cheevos_username = \"$rac_user\"" "$_cfw" 2>/dev/null; then
		rac_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"
		_token="$(rac_login_token "$rac_user" "$rac_pass")"
		if [ -n "$_token" ]; then
			printf 'cheevos_username = "%s"\ncheevos_token = "%s"\n' "$rac_user" "$_token" > "$_cfw"
			log_message "DSperate: fetched a RetroAchievements token for $rac_user"
		else
			rm -f "$_cfw"
			log_message "DSperate: RetroAchievements login failed for $rac_user"
		fi
	fi
	[ -f "$_cfw" ] && export DS_CHEEVOS_CFW_CONFIG="$_cfw"
}

get_video_effect() {
	_setting="$(jq -r '.menuOptions.dsperateVideoEffect.selected // "None"' "${EMU_JSON_PATH:-/mnt/SDCARD/Emu/NDS/config.json}")"

    _override=$(jq -r --arg game "$GAME" ".menuOptions.dsperateVideoEffect.overrides[\$game]" "${EMU_JSON_PATH:-/mnt/SDCARD/Emu/NDS/config.json}")
    if [ -n "$_override" ] && [ "$_override" != "null" ]; then
        _setting="$_override"
    fi

	echo "$_setting"
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

	seed_dsperate_config
	prepare_dsperate_cheevos

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

	# shared arguments for all DSperate invocations
	set -- "$_rom" \
		--fullscreen

	_video_effect="$(get_video_effect)"
	case "$_video_effect" in
		"None") ;;
		"Antialiasing") set -- "$@" --aa --seam blend ;;
		"Bilinear") set -- "$@" --linear ;;
		"Subtle Grid") set -- "$@" --lcd-grid 0.15 ;;
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
		export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
		./dsperate.a30 "$@" --config "/mnt/SDCARD/Saves/dsperate/a30.ini" > "$(emu_log_file)" 2>&1
	else
		case "$DEVICE_NUM_ANALOG_STICKS" in
			"0") _config_path="/mnt/SDCARD/Saves/dsperate/no-sticks.ini"
				grep -q "rg28xx" /etc/baseos-release && export DS_ROTATE=270
				;;
			"1") _config_path="/mnt/SDCARD/Saves/dsperate/one-stick.ini"  ;;
			*)   _config_path="/mnt/SDCARD/Saves/dsperate/two-sticks.ini" ;;
		esac
		export LD_LIBRARY_PATH="$EMU_DIR/lib64:$LD_LIBRARY_PATH"
		./dsperate "$@" --config "$_config_path" > "$(emu_log_file)" 2>&1
	fi

	rm -rf "$DSPERATE_TMP_DIR"
	sync
}
