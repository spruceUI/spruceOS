#!/bin/sh

. /mnt/SDCARD/spruce/scripts/emu/lib/core_mappings.sh
# Requires globals:
#   PLATFORM
#   BRAND
#   CORE
#   EMU_DIR
#   ROM_FILE
#   EMU_JSON_PATH
#   DISPLAY_ASPECT_RATIO
#   LD_LIBRARY_PATH
#
# Requires functions:
#   get_config_value
#   log_message
#   pin_to_dedicated_cores
#
# Provides:
#   prepare_ra_config
#   run_retroarch
#   ready_architecture_dependent_states
#   stash_architecture_dependent_states
#   load_n64_controller_profile
#   save_custom_n64_controller_profile

export RA_DIR="/mnt/SDCARD/RetroArch"

# ── sysfs rumble env setup ─────────────────────────────────────────
# Export the right env vars so RetroArch's sysfs rumble fallback patch
# knows which hardware interface to use for this device.

setup_rumble_env() {
	case "$PLATFORM" in
		"SmartProS")
			export RUMBLE_MOTOR_SCALE="/sys/class/motor/max_scale"
			export RUMBLE_MOTOR_LEVEL="/sys/class/motor/level"
			;;
		"A30")
			export RUMBLE_TIMED_PATH="/sys/devices/virtual/timed_output/vibrator/enable"
			;;
		"SmartPro"|"Brick"|"BrickPro"|"Zero28"|"Flip")
			export RUMBLE_SYSFS_PATH="/sys/class/gpio/${RUMBLE_GPIO}/value"
			;;
	esac
}

prepare_ra_config() {
	case "$PLATFORM" in
    	"Anbernic"*) export PLATFORM_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-AnbernicRG_XX-universal.cfg" ;;
		*) 			 export PLATFORM_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg" ;;
	esac

	# Set up RetroAchievements based on spruceUI config
	rac_mode="$(get_config_value '.menuOptions."RetroAchievements Settings".modeToggle.selected' "Manual")"
	rac_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
	rac_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"
	log_message "Cheevos mode is $rac_mode" -v
	case "$rac_mode" in
		"Disabled")
			# disable cheevos but leave everything else alone
			TMP_CFG="$(mktemp)"
			if sed -e "s|^cheevos_enable.*|cheevos_enable = \"false\"|" "$PLATFORM_CFG" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PLATFORM_CFG"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		"Softcore")
			TMP_CFG="$(mktemp)"
			if sed \
				-e "s|^cheevos_enable.*|cheevos_enable = \"true\"|" \
				-e "s|^cheevos_hardcore_mode_enable.*|cheevos_hardcore_mode_enable = \"false\"|" \
				-e "s|^cheevos_username.*|cheevos_username = \"$rac_user\"|" \
				-e "s|^cheevos_password.*|cheevos_password = \"$rac_pass\"|" \
			"$PLATFORM_CFG" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PLATFORM_CFG"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		"Hardcore")
			TMP_CFG="$(mktemp)"
			if sed \
				-e "s|^cheevos_enable.*|cheevos_enable = \"true\"|" \
				-e "s|^cheevos_hardcore_mode_enable.*|cheevos_hardcore_mode_enable = \"true\"|" \
				-e "s|^cheevos_username.*|cheevos_username = \"$rac_user\"|" \
				-e "s|^cheevos_password.*|cheevos_password = \"$rac_pass\"|" \
			"$PLATFORM_CFG" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PLATFORM_CFG"
			else
				rm -f "$TMP_CFG"
			fi
			;;
	esac

	# Set auto save state based on spruceUI config
	auto_save="$(get_config_value '.menuOptions."Emulator Settings".raAutoSave.selected' "Custom")"
	log_message "auto save setting is $auto_save" -v
	if [ "$auto_save" = "True" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_save.*|savestate_auto_save = "true"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	elif [ "$auto_save" = "False" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_save.*|savestate_auto_save = "false"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	fi

	# Set auto load state based on spruceUI config
	auto_load="$(get_config_value '.menuOptions."Emulator Settings".raAutoLoad.selected' "Custom")"
	log_message "auto load setting is $auto_load" -v
	if [ "$auto_load" = "True" ] && [ "$rac_mode" != "Hardcore" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "true"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	elif [ "$auto_load" = "False" ] || [ "$rac_mode" = "Hardcore" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "false"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	fi

	# Set hotkey enable button based on spruceUI config
	case "$BRAND" in
		"TrimUI" | "GKD")
			hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyTrimUI.selected' "Menu")"
			;;
		"Miyoo" | "Anbernic")
			hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyMiyoo.selected' "Select")"
			;;
	esac
	log_message "ra hotkey enable button is $hotkey_enable" -v

	case "$hotkey_enable" in
		"Select")
			TMP_CFG="$(mktemp)"
			sed "s|^$RA_HOTKEY_LINE = .*|$RA_HOTKEY_LINE = \"$RA_SELECT_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
			mv "$TMP_CFG" "$PLATFORM_CFG"
			;;
		"Start")
			TMP_CFG="$(mktemp)"
			sed "s|^$RA_HOTKEY_LINE = .*|$RA_HOTKEY_LINE = \"$RA_START_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
			mv "$TMP_CFG" "$PLATFORM_CFG"
			;;
		"Menu")
			TMP_CFG="$(mktemp)"
			sed "s|^$RA_HOTKEY_LINE = .*|$RA_HOTKEY_LINE = \"$RA_HOME_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
			mv "$TMP_CFG" "$PLATFORM_CFG"
		;;
		*) ;;
	esac

	# Handle resolution and rotation for Anbernic H700 devices
	case "$PLATFORM" in
		*"Anbernic"*)
			TMP_CFG="$(mktemp)"
			if [ "$PLATFORM" = "AnbernicRG28XX" ]; then
				rot="1"
				vid_x="640"
				vid_y="480"
			else
				rot="0"
				vid_x="0"
				vid_y="0"
			fi

			if sed \
				-e "s|^video_rotation.*|video_rotation = \"$rot\"|" \
				-e "s|^video_fullscreen_x.*|video_fullscreen_x = \"$vid_x\"|" \
				-e "s|^video_fullscreen_y.*|video_fullscreen_y = \"$vid_y\"|" \
				"$PLATFORM_CFG" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PLATFORM_CFG"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		*) ;;
	esac
	sync
}

# Every H700 Anbernic pad reports the same SDL name ("ANBERNIC-keys") and GUID,
# so RetroArch cannot pick a per-model autoconfig by itself, and it re-applies
# the name-matched autoconfig when the pad connects (overriding any --appendconfig
# binds). So write the autoconfig that matches the detected model before launch.
# Face/dpad/shoulders/start/select and the left stick are identical across the
# line; only triggers and stick-clicks move. Indices verified on the CubeXX and
# cross-checked against MustardOS's per-model sdl_map.
write_baseos_ra_autoconfig() {
	ac="$RA_DIR/.retroarch/autoconfig/sdl2/ANBERNIC-keys.cfg"
	[ -d "${ac%/*}" ] || return 0

	# Shared across every model
	common='input_driver = "sdl2"
input_device = "ANBERNIC-keys"
input_vendor_id = "1"
input_product_id = "1"
input_a_btn = "3"
input_b_btn = "4"
input_x_btn = "6"
input_y_btn = "5"
input_l_btn = "7"
input_r_btn = "8"
input_select_btn = "9"
input_start_btn = "10"
input_up_btn = "h0up"
input_down_btn = "h0down"
input_left_btn = "h0left"
input_right_btn = "h0right"
input_l_x_plus_axis = "+0"
input_l_x_minus_axis = "-0"
input_l_y_plus_axis = "+1"
input_l_y_minus_axis = "-1"'

	# Name the stickless models and let everything else take the stick layout.
	# Most of the XX line has sticks, so an unrecognised or future target is
	# likelier to be right that way round than the reverse.
	case "$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null)" in
		rg28xx|rg34xx|rg35xxplus|rg35xxsp|rgsp)
			# Stickless models: no L3/R3 or right stick, L2/R2 stay at b12/b13.
			printf '%s\ninput_l2_btn = "12"\ninput_r2_btn = "13"\n' "$common" > "$ac"
			;;
		*)
			# Analog-stick models: L3/R3 take b12/b15, L2/R2 shift to b13/b14,
			# and there is a right stick on axes 2/3.
			printf '%s\ninput_l2_btn = "13"\ninput_r2_btn = "14"\ninput_l3_btn = "12"\ninput_r3_btn = "15"\ninput_r_x_plus_axis = "+2"\ninput_r_x_minus_axis = "-2"\ninput_r_y_plus_axis = "+3"\ninput_r_y_minus_axis = "-3"\n' "$common" > "$ac"
			;;
	esac
}

# The 32-bit RetroArch needs a different joypad driver, so it needs its own
# autoconfig. The 32-bit SDL2 we ship for BaseOS dlopens libudev and enumerates
# nothing where no udevd runs - verified on a CubeXX, with and without
# SDL_JOYSTICK_DISABLE_UDEV - while RetroArch's linuxraw driver reads the legacy
# /dev/input/js0 and finds the pad as "ANBERNIC-keys".
#
# linuxraw numbers buttons in kernel order, matching neither the udev nor the
# sdl2 profile, and linuxraw_joypad.c has no hat support at all, so the d-pad
# binds as axes rather than h0. The stick-model numbers below are not guesses:
# they were read straight out of the kernel's own joydev tables on a CubeXX with
# JSIOCGBTNMAP and JSIOCGAXMAP, then matched to the evdev codes this line
# reports in AnbernicXXCommon.cfg.
#
# The stickless numbers ARE derived rather than measured. Those models omit L3
# (evdev 313) and R3 (316) and the four stick axes, and joydev assigns indices
# in ascending evdev-code order, so everything above MENU shifts down by one and
# the d-pad lands on axes 0/1. Worth checking on a stickless unit.
write_baseos_ra_autoconfig_linuxraw() {
	ac="$RA_DIR/.retroarch/autoconfig/linuxraw/ANBERNIC-keys.cfg"
	mkdir -p "${ac%/*}" 2>/dev/null || return 0

	# Shared across every model. RetroArch reports this pad as (0/0).
	common='input_driver = "linuxraw"
input_device = "ANBERNIC-keys"
input_vendor_id = "0"
input_product_id = "0"
input_a_btn = "0"
input_b_btn = "1"
input_y_btn = "2"
input_x_btn = "3"
input_l_btn = "4"
input_r_btn = "5"
input_select_btn = "6"
input_start_btn = "7"'

	# Stickless models named; everything else, known or new, takes the stick
	# layout. See write_baseos_ra_autoconfig for the reasoning.
	case "$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null)" in
		rg28xx|rg34xx|rg35xxplus|rg35xxsp|rgsp)
			# Stickless models: no L3/R3, so L2/R2 shift to 9/10.
			#
			# The d-pad is still axes 3 and 4, NOT 0 and 1. joydev numbers axes
			# by ascending ABS code, and these pads report ABS_RX, ABS_RY,
			# ABS_RZ, ABS_HAT0X, ABS_HAT0Y - so the hat lands at 3/4 with three
			# unused axes ahead of it, rather than at 0/1 as you would expect
			# from "no sticks means the d-pad is the only axis pair". Measured
			# on an RG SP: axes=5, and only 3 and 4 ever move.
			printf '%s\ninput_l2_btn = "9"\ninput_r2_btn = "10"\ninput_left_axis = "-3"\ninput_right_axis = "+3"\ninput_up_axis = "-4"\ninput_down_axis = "+4"\n' "$common" > "$ac"
			;;
		*)
			# Analog-stick models: L3/L2/R2/R3 at 9-12, sticks on axes 0-3,
			# d-pad on axes 4/5.
			printf '%s\ninput_l3_btn = "9"\ninput_l2_btn = "10"\ninput_r2_btn = "11"\ninput_r3_btn = "12"\ninput_l_x_plus_axis = "+0"\ninput_l_x_minus_axis = "-0"\ninput_l_y_plus_axis = "+1"\ninput_l_y_minus_axis = "-1"\ninput_r_x_plus_axis = "+2"\ninput_r_x_minus_axis = "-2"\ninput_r_y_plus_axis = "+3"\ninput_r_y_minus_axis = "-3"\ninput_left_axis = "-4"\ninput_right_axis = "+4"\ninput_up_axis = "-5"\ninput_down_axis = "+5"\n' "$common" > "$ac"
			;;
	esac
}

# RetroArch's hotkey binds are RAW joypad button indices - unlike the player
# binds, they do not go through the joypad autoconfig - so the one number in
# AnbernicXXCommon.cfg cannot suit every driver this line runs.
#
# udev and linuxraw number this pad identically, so the stock image and the
# 32-bit BaseOS build both take the shipped value. The 64-bit build drives the
# pad through SDL2, which enumerates the volume and power keys on this node
# before the pad's own buttons and so numbers everything three higher. Select is
# 6 under udev and 9 under SDL2 - which is why the default landed on X for
# anyone on BaseOS with the 64-bit build, the configuration most XX users have.
#
# The action binds carry the same offset, so they move too. Their shipped values
# describe a coherent layout under udev numbering - menu on X, exit on A, load on
# L1, save on R1, fps on Y, fast forward on R2, matching what every other spruce
# device binds - and that is the layout reproduced here. Untranslated, the menu
# landed on A and exit and fps fell on the volume keys, which are not on the pad.
#
# Read every number out of the sdl2 autoconfig RetroArch is about to load, by
# name, so these cannot drift away from the player binds and so the triggers come
# out right - the offset is not a flat +3 for them, since the stick-click binds
# interleave. prepare_ra_config has already written the udev-numbered values;
# this corrects them once the binary is known, which is why it lives here rather
# than there.
#
# "Menu" and "Custom" are deliberately left alone: no model on this line has a
# Menu button, and Custom exists so the user can bind it inside RetroArch.
apply_xx_hotkey_for_driver() {
	ac="$1"
	[ -f "$ac" ] || return 0
	[ -f "$PLATFORM_CFG" ] || return 0

	_btn() { sed -n "s/^input_$2_btn = \"\([0-9]*\)\".*/\1/p" "$1" | head -n 1; }

	case "$(get_config_value '.menuOptions."Emulator Settings".raHotkeyMiyoo.selected' "Select")" in
		"Select") mod="$(_btn "$ac" select)"; modname="Select" ;;
		"Start")  mod="$(_btn "$ac" start)";  modname="Start" ;;
		*)        mod=""; modname="unchanged" ;;
	esac

	hk_a="$(_btn "$ac" a)"; hk_y="$(_btn "$ac" y)"; hk_x="$(_btn "$ac" x)"
	hk_l="$(_btn "$ac" l)"; hk_r="$(_btn "$ac" r)"; hk_r2="$(_btn "$ac" r2)"

	set --
	[ -n "$mod"   ] && set -- "$@" -e "s|^input_enable_hotkey_btn = .*|input_enable_hotkey_btn = \"$mod\"|"
	[ -n "$hk_a"  ] && set -- "$@" -e "s|^input_exit_emulator_btn = .*|input_exit_emulator_btn = \"$hk_a\"|"
	[ -n "$hk_y"  ] && set -- "$@" -e "s|^input_fps_toggle_btn = .*|input_fps_toggle_btn = \"$hk_y\"|"
	[ -n "$hk_x"  ] && set -- "$@" -e "s|^input_menu_toggle_btn = .*|input_menu_toggle_btn = \"$hk_x\"|"
	[ -n "$hk_l"  ] && set -- "$@" -e "s|^input_load_state_btn = .*|input_load_state_btn = \"$hk_l\"|"
	[ -n "$hk_r"  ] && set -- "$@" -e "s|^input_save_state_btn = .*|input_save_state_btn = \"$hk_r\"|"
	[ -n "$hk_r2" ] && set -- "$@" -e "s|^input_toggle_fast_forward_btn = .*|input_toggle_fast_forward_btn = \"$hk_r2\"|"
	[ $# -eq 0 ] && return 0

	TMP_CFG="$(mktemp)"
	if sed "$@" "$PLATFORM_CFG" > "$TMP_CFG"; then
		mv "$TMP_CFG" "$PLATFORM_CFG"
		log_message "ra hotkeys renumbered for sdl2: enable=$modname($mod) exit=$hk_a menu=$hk_x load=$hk_l save=$hk_r fps=$hk_y ff=$hk_r2" -v
	else
		rm -f "$TMP_CFG"
	fi
}

# BaseOS has no udevd, so the universal cfg's udev input drivers find no pad.
# Overlay the sdl2 input drivers on top without touching the shared cfg. The
# 32-bit build gets its own overlay: its SDL2 cannot see the pad here, so it
# drives the joypad through linuxraw instead. One overlay either way, because
# only the last --appendconfig would win.
#
# Shared rather than inlined in run_retroarch because the standalone RetroArch
# app launchers build their own command line and skipped all of this. The 32-bit
# app was therefore launching with the universal cfg's sdl2 joypad driver, which
# cannot see the pad on BaseOS - so it had no controls at all, while the same
# binary launched with a game worked fine.
#
# Requires RA_BIN and RA_DIR; appends to RA_PARAMS.
apply_baseos_ra_overlay() {
	[ -n "$SPRUCE_BASEOS" ] || return 0

	case "$RA_BIN" in
		ra32.*) baseos_overlay="retroarch-AnbernicRG_XX-baseos32.cfg" ;;
		*)      baseos_overlay="retroarch-AnbernicRG_XX-baseos.cfg" ;;
	esac
	[ -f "$RA_DIR/platform/$baseos_overlay" ] || return 0

	RA_PARAMS="${RA_PARAMS} --appendconfig ${RA_DIR}/platform/$baseos_overlay"
	case "$RA_BIN" in
		ra32.*)
			# linuxraw numbers the pad exactly as udev does, so the shipped
			# RA_SELECT_VAL/RA_START_VAL already suit it - nothing to correct.
			write_baseos_ra_autoconfig_linuxraw
			;;
		*)
			write_baseos_ra_autoconfig
			apply_xx_hotkey_for_driver "$RA_DIR/.retroarch/autoconfig/sdl2/ANBERNIC-keys.cfg"
			;;
	esac
}

run_retroarch() {
	prepare_ra_config 2>/dev/null

	# Apply per-game or system-wide RA build selection. The binary names are
	# device-overridable because "64-bit" is not always the universal build -
	# Anbernic XX under BaseOS runs the H700-tuned ra64.h700. Hardcoding the
	# name here would quietly swap that back for the generic binary, which
	# still runs, so the only symptom would be lost performance.
	case "$RA_BUILD" in
		"32-bit") export RA_BIN="${RA_BIN_32:-ra32.universal}" ;;
		"64-bit") export RA_BIN="${RA_BIN_64:-ra64.universal}" ;;
	esac

	use_igm="$(get_config_value '.menuOptions."Emulator Settings".raInGameMenu.selected' "True")"

	# Sync IGM flag file with config setting
	IGM_FLAG="/mnt/SDCARD/RetroArch/IGM.txt"
	if [ "$use_igm" = "True" ] && [ "$CORE" != "dosbox_pure" ]; then
		touch "$IGM_FLAG"
	else
		rm -f "$IGM_FLAG"
	fi

	setup_for_retroarch
	cd "$RA_DIR"

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

	pin_to_dedicated_cores "$RA_BIN"

	ra_start_setup_saves_and_states_for_core_differences

	log_message "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\""
	log_message "export PATH=\"$PATH\""
	#Swap below if debugging
	
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$RA_DIR"

	setup_rumble_env

	RA_PARAMS=""
	if [ "$VERBOSE_EMU" = "1" ]; then
		RA_PARAMS="-v"
	fi
	case "$PLATFORM" in
		"Pixel2"|"Flip"|"Miniloong"|"SmartPro"|"SmartProS"|"Brick"|"BrickPro"|"A30"|"MiyooMini"|"RGB30"|"Anbernic"*)
			RA_PARAMS="${RA_PARAMS} --config ${PLATFORM_CFG}"
			;;
	esac

	apply_baseos_ra_overlay

	# Prevent SDL2 from applying Xbox 360 gamecontroller mapping to the
	# MIYOO Pad1 virtual joypad (shares vendor:product 045e:028e with Xbox).
	# Without this, SDL2 remaps buttons incorrectly (e.g. X→L1, Y→R1).
	case "$PLATFORM" in
		"A30")
			export SDL_GAMECONTROLLER_IGNORE_DEVICES=0x045E/0x028E
			;;
	esac

	if [ "$VERBOSE_EMU" = "1" ]; then
		log_message "Running CMD: HOME=\"$RA_DIR/\" \"$RA_DIR/$RA_BIN\" $RA_PARAMS --log-file /mnt/SDCARD/Saves/spruce/retroarch.log -L \"$CORE_PATH\" \"$ROM_FILE\""
		HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" $RA_PARAMS --log-file /mnt/SDCARD/Saves/spruce/retroarch.log -L "$CORE_PATH" "$ROM_FILE"
	else
		log_message "Running CMD: HOME=\"$RA_DIR/\" \"$RA_DIR/$RA_BIN\" $RA_PARAMS -L \"$CORE_PATH\" \"$ROM_FILE\""
		HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" $RA_PARAMS -L "$CORE_PATH" "$ROM_FILE"
	fi
	backup_rac_creds_to_spruce_cfg
	ra_close_setup_saves_and_states_for_core_differences
}

ra_start_setup_saves_and_states_for_core_differences() {
	cached_core_folder=$(get_cached_core_path)
	
    # Get only the filename of the core
    core_basename=$(basename "$CORE_PATH")
	current_core_folder=$(get_core_folder "$core_basename")

    if [ "$cached_core_folder" != "$current_core_folder" ]; then
		log_message "Core changed : CURRENT = $current_core_folder, CACHED = $cached_core_folder"

		handle_changed_core "$cached_core_folder" "$current_core_folder" 
		cache_core_path "$current_core_folder"
	fi

	ready_architecture_dependent_states
}

ra_close_setup_saves_and_states_for_core_differences(){
	stash_architecture_dependent_states
}

cache_core_path() {
    core=$1

    cache_dir="/mnt/SDCARD/Saves/spruce/last_core_run/${EMU_NAME}"
    mkdir -p "$cache_dir"

    # Get only the basename of the ROM file
    rom_basename=$(basename "$ROM_FILE")

    cache_file="${cache_dir}/${rom_basename}"

    echo "$core" > "$cache_file"
}


get_cached_core_path() {
	# Get only the basename of the ROM file
    rom_basename=$(basename "$ROM_FILE")

    cache_file="/mnt/SDCARD/Saves/spruce/last_core_run/${EMU_NAME}/${rom_basename}"

    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
		core_basename=$(basename "$CORE_PATH")
		current_core_folder=$(get_core_folder "$core_basename")
		cache_core_path "$current_core_folder"

        echo "$current_core_folder"
    fi
}

transfer_save(){
	cached_core_folder="$1"
	current_core_folder="$2"

	KEEP_SAVES_BETWEEN_CORES="$(get_config_value '.menuOptions."Emulator Settings".keepSavesBetweenCores.selected' "Prompt")"
	if [ "$KEEP_SAVES_BETWEEN_CORES" = "Always" ]; then
		return 0
	elif [ "$KEEP_SAVES_BETWEEN_CORES" = "Never" ]; then
		return 1
	else
		start_pyui_message_writer
		log_and_display_message "RetroArch core changed!\n$cached_core_folder to $current_core_folder\nWould you like to transfer your old save?\n(This will remove the auto save-state).\n\nPress A to transfer, or B to continue"
		if confirm; then
			log_and_display_message "Transferring saves from\n$cached_core_folder to $current_core_folder"
			stop_pyui_message_writer
			return 0
		else
			log_and_display_message "Not transferring saves. Launching with new core."
			stop_pyui_message_writer
			return 1
		fi

	fi
}

handle_changed_core() {

	cached_core_folder="$1"
	current_core_folder="$2"

	if transfer_save "$1" "$2"; then
		log_message "Syncing saves between cores as per user setting."

		rom_basename=$(basename "$ROM_FILE")
		rom_name="${rom_basename%.*}" 

		timestamp=$(date +%s)

		saves_dir="/mnt/SDCARD/Saves/saves"
		# Find the cached save (any extension) in the cached core folder
		cached_save_file=$(find "$saves_dir/$cached_core_folder/" -maxdepth 1 -type f -name "${rom_name}.*" | head -n 1)
		if [ -n "$cached_save_file" ]; then

			# --- Handle Saves ---
			# Find the current save (any extension) in the current core folder
			current_save_file=$(find "$saves_dir/$current_core_folder/" -maxdepth 1 -type f -name "${rom_name}.*" | head -n 1)
			if [ -n "$current_save_file" ]; then
				mv "$current_save_file" "${current_save_file}.bak-$timestamp"
				log_message "Moved current save to ${current_save_file}.bak-$timestamp"
			else
				log_message "No current save exists in $current_core_folder for $rom_name"
			fi

			cp "$cached_save_file" "$saves_dir/$current_core_folder/"
			log_message "Copied save from $cached_save_file to $current_core_folder"

			# --- Handle States ---
			states_dir="/mnt/SDCARD/Saves/states"

			# Find the current state file (any extension, typically .auto) in current core folder
			current_state_file=$(find "$states_dir/$current_core_folder/" -maxdepth 1 -type f -name "${rom_name}.*" | head -n 1)
			if [ -n "$current_state_file" ]; then
				mv "$current_state_file" "${current_state_file}.bak-$timestamp"
				log_message "Moved current state to ${current_state_file}.bak-$timestamp"
			else
				log_message "No current state exists in $states_dir/$current_core_folder for $rom_name"
			fi

			# No state copy from cached folder, since cores rarely share state files

		else
			log_message "No cached save exists in $cached_core_folder for $rom_name so not moving any saves/states"
		fi
	fi
}


CORE_LIST="PCSX-ReARMed RACE fake-08 ChimeraSNES"

ready_architecture_dependent_states() {
    STATES="/mnt/SDCARD/Saves/states"
    SAVES="/mnt/SDCARD/Saves/saves"

    # Derive suffix from RA binary, not platform architecture
    case "$RA_BIN" in
        ra32.*) SUFFIX="32" ;;
        ra64.*) SUFFIX="64" ;;
        *)
            SUFFIX="64"
            [ "$PLATFORM_ARCHITECTURE" = "armhf" ] && SUFFIX="32"
            ;;
    esac

    # List of cores to handle
    for CORE in ${CORE_LIST}; do
	    # Loop over both STATES and SAVES
        for BASE in "$STATES" "$SAVES"; do
            DIR_SUFFIX="$BASE/$CORE-$SUFFIX"
            DIR_BASE="$BASE/$CORE"

            # Only for SAVES: copy existing base files into SUFFIX dir if empty
			# This is because we used to have a common saves dir, so if it's the
			# first time it's being made, it means the user has just upgraded
			# Alternatively we could have users manually do this
            [ ! -d "$DIR_SUFFIX" ] && mkdir -p "$DIR_SUFFIX"
            if [ "$BASE" = "$SAVES" ] && [ -d "$DIR_BASE" ] && [ "$(ls -A "$DIR_SUFFIX")" = "" ]; then
                cp -a "$DIR_BASE/." "$DIR_SUFFIX/"
            fi

            [ ! -d "$DIR_BASE" ] && mkdir -p "$DIR_BASE"
            mount --bind "$DIR_SUFFIX" "$DIR_BASE"
        done
    done
}

stash_architecture_dependent_states() {
    STATES="/mnt/SDCARD/Saves/states"
    SAVES="/mnt/SDCARD/Saves/saves"

    # List of cores to handle
    for CORE in $CORE_LIST; do
		for BASE in "$STATES" "$SAVES"; do
			mkdir -p "$BASE/$CORE-$SUFFIX"
			umount "$BASE/$CORE"
        done
    done
}

backup_rac_creds_to_spruce_cfg() {

	# if spruce setting for RAC mode is auto or disabled, do nothing.
	rac_mode="$(get_config_value '.menuOptions."RetroAchievements Settings".modeToggle.selected' "Manual")"
	case "$rac_mode" in
		"Softcore"|"Hardcore") ;;
		*) return ;;
	esac

	ra_user="$(grep '^cheevos_username' "$PLATFORM_CFG" | sed 's/.*= *"\(.*\)".*/\1/')"
	ra_pass="$(grep '^cheevos_password' "$PLATFORM_CFG" | sed 's/.*= *"\(.*\)".*/\1/')"
	json_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
	json_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"

	# if neither user nor pass have been updated during RA runtime, do nothing.
	[ "$ra_user" = "$json_user" ] && [ "$ra_pass" = "$json_pass" ] && return

	# don't update spruce json if either user or pass was blanked during runtime.
	[ -z "$ra_user" ] && return
	[ -z "$ra_pass" ] && return

	log_message "Cheevos creds updated during runtime. Syncing back to spruce-config.json."
	SPRUCE_JSON="/mnt/SDCARD/Saves/spruce/spruce-config.json"
	TMP_JSON="$(mktemp)"
	jq \
		--arg user "$ra_user" \
		--arg pass "$ra_pass" \
		'.menuOptions["RetroAchievements Settings"].username.selected = $user
		 | .menuOptions["RetroAchievements Settings"].password.selected = $pass' \
		"$SPRUCE_JSON" > "$TMP_JSON" && mv "$TMP_JSON" "$SPRUCE_JSON"
}

load_n64_controller_profile() {
	profile="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	case "$profile" in
		*"Classic"*) profile_name="Classic" ;;
		*"Action"*) profile_name="Action" ;;
		*"Custom"*) return 0 ;;	# don't overwrite the remap if Custom is selected
		*) return 0 ;; # exit early if jq fails or config is broken
	esac

	SRC="/mnt/SDCARD/Emu/N64/remaps"
	DST="/mnt/SDCARD/RetroArch/.retroarch/config/remaps"

	for dir in "$DST"/*; do
		[ ! -d "$dir" ] && continue
		dirname="$(basename "$dir")"
		case "$dirname" in
			*"n64"*|*"N64"*)
				cp -f "${SRC}/${profile_name}.rmp" "${dir}/${dirname}.rmp"
			;;
			*) ;; # if core display name doesn't have N64 in it, do nothing.
		esac
	done
}

save_custom_n64_controller_profile() {
	profile="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	case "$profile" in 
		*"Custom"* ) ;; # continue to remainder of function
		* ) return 0 ;; # exit function early; no need to back up remap
	esac

	REMAP_BACKUP="/mnt/SDCARD/Emu/N64/remaps/Custom.rmp"
	REMAP_DIR="/mnt/SDCARD/RetroArch/.retroarch/config/remaps"

	case "$CORE" in
		"km_ludicrousn64_2k22_xtreme_amped") 	core_name="LudicrousN64 2K22 Xtreme Amped" ;;
		"km_parallel_n64_xtreme_amped_turbo") 	core_name="ParaLLEl N64 Xtreme Amped" ;;
		"mupen64plus") 							core_name="Mupen64Plus GLES2" ;;
		"parallel_n64") 						core_name="ParaLLEl N64" ;;
		"mupen64plus_next") 					core_name="Mupen64Plus-Next" ;;
		*) return 0 ;; # if not a known N64 core, do nothing
	esac

	cp -f "${REMAP_DIR}/${core_name}/${core_name}.rmp" "$REMAP_BACKUP"
}
