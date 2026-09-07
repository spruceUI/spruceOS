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
# binds). So write the autoconfig that matches the detected layout before launch.
# Face/dpad/shoulders/start/select and the left stick are identical across the
# line; only triggers and stick-clicks move. Indices verified on the CubeXX and
# cross-checked against MustardOS's per-model sdl_map; the layout itself comes
# from XX_PAD_LAYOUT in AnbernicXXCommon.cfg, the one place that classifies
# models.
write_baseos_ra_autoconfig() {
	ac="$RA_DIR/.retroarch/autoconfig/sdl2/ANBERNIC-keys.cfg"
	[ -d "${ac%/*}" ] || return 0

	# Shared across every layout. The comment line records MENU's index for
	# apply_xx_hotkeys_from_autoconfig: RetroArch has no player bind for a
	# MENU/guide button, so the autoconfig vocabulary cannot carry it, and
	# RetroArch skips comment lines when it reads the file.
	common='input_driver = "sdl2"
# spruce_menu_index = "11"
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

	case "$XX_PAD_LAYOUT" in
		nostick)
			# No L3/R3 or right stick, L2/R2 at b12/b13.
			printf '%s\ninput_l2_btn = "12"\ninput_r2_btn = "13"\n' "$common" > "$ac"
			;;
		1stick)
			# RG40XX V: L3 at b12 shifts L2/R2 to b13/b14; there is no R3 and
			# b15 is the MENU tap pulse (KEY_GOTO), so nothing may bind it.
			printf '%s\ninput_l2_btn = "13"\ninput_r2_btn = "14"\ninput_l3_btn = "12"\n' "$common" > "$ac"
			;;
		*)
			# Two sticks: L3/R3 take b12/b15, L2/R2 shift to b13/b14, and there
			# is a right stick on axes 2/3.
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
# binds as axes rather than h0. The two-stick numbers are not guesses: they were
# read straight out of the kernel's own joydev tables on a CubeXX with
# JSIOCGBTNMAP and JSIOCGAXMAP, then matched to the evdev codes this line
# reports in AnbernicXXCommon.cfg.
#
# The stickless and one-stick numbers ARE derived rather than measured. Those
# models omit R3 (evdev 316) and, on stickless models, L3 (313) and the stick
# axes; joydev assigns indices in ascending evdev-code order, so everything
# above MENU shifts down by one per missing key. Stickless pads still report
# ABS_RX/RY/RZ ahead of the hat (measured on an RG SP: axes=5, only 3 and 4
# ever move), and the one-stick RG40XX V is assumed to report the same six axes
# as the two-stick models. Worth checking on a V.
write_baseos_ra_autoconfig_linuxraw() {
	ac="$RA_DIR/.retroarch/autoconfig/linuxraw/ANBERNIC-keys.cfg"
	mkdir -p "${ac%/*}" 2>/dev/null || return 0

	# Shared across every layout. RetroArch reports this pad as (0/0). The
	# comment line records MENU's index (see write_baseos_ra_autoconfig).
	common='input_driver = "linuxraw"
# spruce_menu_index = "8"
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

	case "$XX_PAD_LAYOUT" in
		nostick)
			# No L3/R3, so L2/R2 shift to 9/10; hat on axes 3/4 behind three
			# unused stick-shaped axes.
			printf '%s\ninput_l2_btn = "9"\ninput_r2_btn = "10"\ninput_left_axis = "-3"\ninput_right_axis = "+3"\ninput_up_axis = "-4"\ninput_down_axis = "+4"\n' "$common" > "$ac"
			;;
		1stick)
			# L3 at 9, L2/R2 at 10/11, no R3 (12 would be the MENU tap pulse);
			# left stick on axes 0/1, hat on 4/5.
			printf '%s\ninput_l3_btn = "9"\ninput_l2_btn = "10"\ninput_r2_btn = "11"\ninput_l_x_plus_axis = "+0"\ninput_l_x_minus_axis = "-0"\ninput_l_y_plus_axis = "+1"\ninput_l_y_minus_axis = "-1"\ninput_left_axis = "-4"\ninput_right_axis = "+4"\ninput_up_axis = "-5"\ninput_down_axis = "+5"\n' "$common" > "$ac"
			;;
		*)
			# Two sticks: L3/L2/R2/R3 at 9-12, sticks on axes 0-3, hat on 4/5.
			printf '%s\ninput_l3_btn = "9"\ninput_l2_btn = "10"\ninput_r2_btn = "11"\ninput_r3_btn = "12"\ninput_l_x_plus_axis = "+0"\ninput_l_x_minus_axis = "-0"\ninput_l_y_plus_axis = "+1"\ninput_l_y_minus_axis = "-1"\ninput_r_x_plus_axis = "+2"\ninput_r_x_minus_axis = "-2"\ninput_r_y_plus_axis = "+3"\ninput_r_y_minus_axis = "-3"\ninput_left_axis = "-4"\ninput_right_axis = "+4"\ninput_up_axis = "-5"\ninput_down_axis = "+5"\n' "$common" > "$ac"
			;;
	esac
}

# RetroArch's hotkey binds are RAW joypad indices - unlike the player binds,
# they do not go through the joypad autoconfig - so no single number in the
# shared universal cfg can suit every driver this line runs. udev (the numbers
# the universal cfg is written in) and linuxraw agree on the buttons but not on
# the d-pad (hat vs axes); the 64-bit SDL2 build numbers everything three
# higher and interleaves the stick clicks with the triggers.
#
# So every hotkey is rewritten by NAME out of the autoconfig RetroArch is about
# to load, whichever driver that is. The layout is the fleet's arm64 standard:
#   modifier + B exit, + A screenshot, + X menu, + Y fps, + L1 load, + R1 save,
#   + L2 slow-motion, + R2 fast-forward, + UP shader, + LEFT/RIGHT state slot.
# A bind whose control the autoconfig does not carry is nulled, so a stickless
# unit never inherits a stick model's number.
#
# The modifier follows the spruce menu option: Menu/Select/Start bind by name,
# MENU being the fleet default and the shipped value. Custom means "leave what
# RetroArch has" - except when the cfg still holds a udev literal spruce itself
# wrote (RA_HOME_VAL/RA_SELECT_VAL/RA_START_VAL), which under SDL2 lands three
# buttons off; that literal is spruce state, not a user choice, and is
# translated the same way. Anything else is a value the user set inside
# RetroArch and is left alone. RetroArch saves the
# translated numbers back on exit, so the next launch sees them as user values
# and the translation is a no-op from then on.
#
# Requires PLATFORM_CFG (the cfg RetroArch is launched with) and the platform
# cfg's RA_SELECT_VAL/RA_START_VAL.
apply_xx_hotkeys_from_autoconfig() {
	ac="$1"
	[ -f "$ac" ] || return 0
	[ -f "$PLATFORM_CFG" ] || return 0

	# Value of an autoconfig bind by control name: "input_<ctl>_btn" first,
	# then "input_<ctl>_axis" (the linuxraw d-pad). Prints "kind value".
	_bind() {
		if [ "$1" = "menu" ]; then
			v="$(sed -n 's/^# spruce_menu_index = "\([^"]*\)".*/\1/p' "$ac" | head -n 1)"
			[ -n "$v" ] && echo "btn $v"
			return
		fi
		v="$(sed -n "s/^input_$1_btn = \"\([^\"]*\)\".*/\1/p" "$ac" | head -n 1)"
		if [ -n "$v" ]; then echo "btn $v"; return; fi
		v="$(sed -n "s/^input_$1_axis = \"\([^\"]*\)\".*/\1/p" "$ac" | head -n 1)"
		[ -n "$v" ] && echo "axis $v"
	}
	# Append sed lines that put hotkey $1 on control $2: whichever of the
	# _btn/_axis pair the autoconfig uses gets the value, the other gets nul.
	# A script file rather than -e arguments, because the expressions carry
	# spaces and busybox sed has no escape for them.
	_put() {
		b="$(_bind "$2")"
		case "$b" in
			"btn "*)  bv="${b#btn }"; av="nul" ;;
			"axis "*) bv="nul"; av="${b#axis }" ;;
			*)        bv="nul"; av="nul" ;;
		esac
		printf 's|^input_%s_btn = .*|input_%s_btn = "%s"|\ns|^input_%s_axis = .*|input_%s_axis = "%s"|\n' \
			"$1" "$1" "$bv" "$1" "$1" "$av" >> "$SEDF"
	}

	SEDF="$(mktemp)"
	_put exit_emulator b
	_put screenshot a
	_put menu_toggle x
	_put fps_toggle y
	_put load_state l
	_put save_state r
	_put toggle_slowmotion l2
	_put toggle_fast_forward r2
	_put shader_toggle up
	_put state_slot_decrease left
	_put state_slot_increase right

	mod=""; modname="unchanged"
	case "$(get_config_value '.menuOptions."Emulator Settings".raHotkeyMiyoo.selected' "Menu")" in
		"Menu")   mod="$(_bind menu)";   modname="Menu" ;;
		"Select") mod="$(_bind select)"; modname="Select" ;;
		"Start")  mod="$(_bind start)";  modname="Start" ;;
		*)
			cur="$(sed -n 's/^input_enable_hotkey_btn = "\([^"]*\)".*/\1/p' "$PLATFORM_CFG" | head -n 1)"
			if [ -n "$RA_HOME_VAL" ] && [ "$cur" = "$RA_HOME_VAL" ]; then
				mod="$(_bind menu)"; modname="Custom(spruce default Menu)"
			elif [ -n "$RA_SELECT_VAL" ] && [ "$cur" = "$RA_SELECT_VAL" ]; then
				mod="$(_bind select)"; modname="Custom(spruce default Select)"
			elif [ -n "$RA_START_VAL" ] && [ "$cur" = "$RA_START_VAL" ]; then
				mod="$(_bind start)"; modname="Custom(spruce default Start)"
			fi
			;;
	esac
	case "$mod" in
		"btn "*) printf 's|^input_enable_hotkey_btn = .*|input_enable_hotkey_btn = "%s"|\n' "${mod#btn }" >> "$SEDF" ;;
	esac

	TMP_CFG="$(mktemp)"
	if sed -f "$SEDF" "$PLATFORM_CFG" > "$TMP_CFG"; then
		mv "$TMP_CFG" "$PLATFORM_CFG"
		log_message "ra hotkeys bound by name from ${ac##*/autoconfig/}: modifier=$modname exit=$(_bind b) shot=$(_bind a) menu=$(_bind x) fps=$(_bind y) load=$(_bind l) save=$(_bind r) slow=$(_bind l2) ff=$(_bind r2) shader=$(_bind up) slot=$(_bind left)/$(_bind right)" -v
	else
		rm -f "$TMP_CFG"
	fi
	rm -f "$SEDF"
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
			write_baseos_ra_autoconfig_linuxraw
			apply_xx_hotkeys_from_autoconfig "$RA_DIR/.retroarch/autoconfig/linuxraw/ANBERNIC-keys.cfg"
			;;
		*)
			write_baseos_ra_autoconfig
			apply_xx_hotkeys_from_autoconfig "$RA_DIR/.retroarch/autoconfig/sdl2/ANBERNIC-keys.cfg"
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
	if [ "$use_igm" = "True" ]; then
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
