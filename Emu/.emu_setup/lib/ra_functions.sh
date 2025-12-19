#!/bin/sh

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
#   backup_ra_config
#   run_retroarch
#   ready_architecture_dependent_states
#   stash_architecture_dependent_states
#   load_n64_controller_profile
#   save_custom_n64_controller_profile

prepare_ra_config() {
	use_igm="$(get_config_value '.menuOptions."Emulator Settings".raInGameMenu.selected' "True")"
	PLATFORM_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
	if [ "$PLATFORM" = "Flip" ] && [ "$use_igm" = "True" ]; then
		CURRENT_CFG="/mnt/SDCARD/RetroArch/ra64.miyoo.cfg"
	elif [ "$PLATFORM" = "MiyooMini" ]; then
		CURRENT_CFG="/mnt/SDCARD/RetroArch/.retroarch/retroarch.cfg"
	else
		CURRENT_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"
	fi

	# Set auto save state based on spruceUI config
	auto_save="$(get_config_value '.menuOptions."Emulator Settings".raAutoSave.selected' "Custom")"
	log_message "auto save setting is $auto_save"
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
	log_message "auto load setting is $auto_load"
	if [ "$auto_load" = "True" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "true"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	elif [ "$auto_load" = "False" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "false"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	fi


	if [ "$PLATFORM" != "MiyooMini" ]; then

		# Set hotkey enable button based on spruceUI config
		case "$BRAND" in
			"TrimUI")
				hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyTrimUI.selected' "Menu")"
				;;
			"Miyoo")
				hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyMiyoo.selected' "Select")"
				;;
		esac
		log_message "ra hotkey enable button is $hotkey_enable"
		case "$PLATFORM" in
			"A30")
				HOTKEY_LINE="input_enable_hotkey"
				SELECT_VAL="rctrl"
				START_VAL="enter"
				HOME_VAL="escape"
				;;
			*)
				HOTKEY_LINE="input_enable_hotkey_btn"
				SELECT_VAL="4"
				START_VAL="6"
				HOME_VAL="5"
				;;
		esac
		case "$hotkey_enable" in
			"Select")
				TMP_CFG="$(mktemp)"
				sed "s|^$HOTKEY_LINE = .*|$HOTKEY_LINE = \"$SELECT_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
				mv "$TMP_CFG" "$PLATFORM_CFG"
				;;
			"Start")
				TMP_CFG="$(mktemp)"
				sed "s|^$HOTKEY_LINE = .*|$HOTKEY_LINE = \"$START_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
				mv "$TMP_CFG" "$PLATFORM_CFG"
				;;
			"Menu")
				TMP_CFG="$(mktemp)"
				sed "s|^$HOTKEY_LINE = .*|$HOTKEY_LINE = \"$HOME_VAL\"|" "$PLATFORM_CFG" > "$TMP_CFG"
				mv "$TMP_CFG" "$PLATFORM_CFG"
			;;
			*) ;;
		esac
	fi
	# copy platform-specific RA config into place where RA wants it to be
	cp -f "$PLATFORM_CFG" "$CURRENT_CFG"
	log_message "copying $PLATFORM_CFG to $CURRENT_CFG"

}

backup_ra_config() {
	# copy any changes to retroarch.cfg made during RA runtime back to platform-specific config
	use_igm="$(get_config_value '.menuOptions."Emulator Settings".raInGameMenu.selected' "True")"
	PLATFORM_CFG="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
	if [ "$PLATFORM" = "Flip" ] && [ "$use_igm" = "True" ]; then
		CURRENT_CFG="/mnt/SDCARD/RetroArch/ra64.miyoo.cfg"
	else
		CURRENT_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"
	fi
	[ -e "$CURRENT_CFG" ] && cp -f "$CURRENT_CFG" "$PLATFORM_CFG"
}

run_retroarch() {

	prepare_ra_config 2>/dev/null

	use_igm="$(get_config_value '.menuOptions."Emulator Settings".raInGameMenu.selected' "True")"

	case "$PLATFORM" in
		"Brick" | "SmartPro" | "SmartProS")
			if [ "$use_igm" = "True" ]; then
				export RA_BIN="ra64.trimui_$PLATFORM"
			else
				export RA_BIN="retroarch.trimui"
				export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/mnt/SDCARD/spruce/flip/lib"
			fi
			if [ "$CORE" = "uae4arm" ]; then
				export LD_LIBRARY_PATH=$EMU_DIR:$LD_LIBRARY_PATH
			elif [ "$CORE" = "genesis_plus_gx" ] && [ "$DISPLAY_ASPECT_RATIO" = "16:9" ]; then
				use_gpgx_wide="$(get_config_value '.menuOptions."Emulator Settings".genesisPlusGXWide.selected' "False")"
				[ "$use_gpgx_wide" = "True" ] && CORE="genesis_plus_gx_wide"
			fi
			# TODO: remove this once profile is set up
			export LD_LIBRARY_PATH=$EMU_DIR/lib64:$LD_LIBRARY_PATH
		;;
		"Flip" )
			if [ "$CORE" = "yabasanshiro" ]; then
				# "Error(s): /usr/miyoo/lib/libtmenu.so: undefined symbol: GetKeyShm" if you try to use non-Miyoo RA for this core
				export RA_BIN="ra64.miyoo"
			elif [ "$use_igm" = "False" ] || [ "$CORE" = "parallel_n64" ]; then
				export RA_BIN="retroarch-flip"
			else
				export RA_BIN="ra64.miyoo"
			fi
			
			if [ "$CORE" = "easyrpg" ]; then
				export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip
			elif [ "$CORE" = "yabasanshiro" ]; then
				export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR/lib64
			fi
		;;
		"A30" )
			if [ "$use_igm" = "False" ] || [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
				export RA_BIN="retroarch"
			else
				export RA_BIN="ra32.miyoo"
			fi
		;;
		"MiyooMini" )
			export RA_BIN="retroarch-miyoomini"
		;;
	esac

	RA_DIR="/mnt/SDCARD/RetroArch"
	cd "$RA_DIR"

	if [ "$PLATFORM" = "A30" ]; then
		CORE_DIR="$RA_DIR/.retroarch/cores"
	elif [ "$PLATFORM" = "MiyooMini" ]; then
		#Might need to change
		CORE_DIR="/mnt/SDCARD/spruce/miyoomini/RetroArch/.retroarch/cores"
	else # 64-bit device
		CORE_DIR="$RA_DIR/.retroarch/cores64"
	fi

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

	if [ "$PLATFORM" != "MiyooMini" ]; then
		pin_to_dedicated_cores "$RA_BIN"
	fi

	#Swap below if debugging new cores
	#HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v --log-file /mnt/SDCARD/Saves/retroarch.log -L "$CORE_PATH" "$ROM_FILE"
	HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$CORE_PATH" "$ROM_FILE"

	backup_ra_config 2>/dev/null
}

ready_architecture_dependent_states() {
	STATES="/mnt/SDCARD/Saves/states"
	if [ "$PLATFORM" = "A30" ]; then 
		[ -d "$STATES/RACE-32" ] && mv "$STATES/RACE-32" "$STATES/RACE"
		[ -d "$STATES/fake-08-32" ] && mv "$STATES/fake-08-32" "$STATES/fake-08"
		[ -d "$STATES/PCSX-ReARMed-32" ] && mv "$STATES/PCSX-ReARMed-32" "$STATES/PCSX-ReARMed"
		[ -d "$STATES/ChimeraSNES-32" ] && mv "$STATES/ChimeraSNES-32" "$STATES/ChimeraSNES"

	else # 64-bit device
		[ -d "$STATES/RACE-64" ] && mv "$STATES/RACE-64" "$STATES/RACE"
		[ -d "$STATES/fake-08-64" ] && mv "$STATES/fake-08-64" "$STATES/fake-08"
		[ -d "$STATES/PCSX-ReARMed-64" ] && mv "$STATES/PCSX-ReARMed-64" "$STATES/PCSX-ReARMed"
		[ -d "$STATES/ChimeraSNES-64" ] && mv "$STATES/ChimeraSNES-64" "$STATES/ChimeraSNES"
	fi
}

stash_architecture_dependent_states() {
	STATES="/mnt/SDCARD/Saves/states"
	if [ "$PLATFORM" = "A30" ]; then 
		[ -d "$STATES/RACE" ] && mv "$STATES/RACE" "$STATES/RACE-32"
		[ -d "$STATES/fake-08" ] && mv "$STATES/fake-08" "$STATES/fake-08-32"
		[ -d "$STATES/PCSX-ReARMed" ] && mv "$STATES/PCSX-ReARMed" "$STATES/PCSX-ReARMed-32"
		[ -d "$STATES/ChimeraSNES" ] && mv "$STATES/ChimeraSNES" "$STATES/ChimeraSNES-32"

	else # 64-bit device
		[ -d "$STATES/RACE" ] && mv "$STATES/RACE" "$STATES/RACE-64"
		[ -d "$STATES/fake-08" ] && mv "$STATES/fake-08" "$STATES/fake-08-64"
		[ -d "$STATES/PCSX-ReARMed" ] && mv "$STATES/PCSX-ReARMed" "$STATES/PCSX-ReARMed-64"
		[ -d "$STATES/ChimeraSNES" ] && mv "$STATES/ChimeraSNES" "$STATES/ChimeraSNES-64"

	fi
}

load_n64_controller_profile() {
	PROFILE="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	[ "$PROFILE" = "Classic (R2 + A, B, X, Y)" ] && PROFILE="Classic"
	[ "$PROFILE" = "Action (A, X, Select, R1)" ] && PROFILE="Action"

	SRC="/mnt/SDCARD/Emu/.emu_setup/n64_controller"
	DST="/mnt/SDCARD/RetroArch/.retroarch/config/remaps"
	LUDI="LudicrousN64 Xtreme Amped"
	PARA="ParaLLEl N64"
	MUPEN="Mupen64Plus GLES2"
	cp -f "${SRC}/${PROFILE}.rmp" "${DST}/${LUDI}/${LUDI}.rmp"
	cp -f "${SRC}/${PROFILE}.rmp" "${DST}/${PARA}/${PARA}.rmp"
	cp -f "${SRC}/${PROFILE}.rmp" "${DST}/${MUPEN}/${MUPEN}.rmp"
}

save_custom_n64_controller_profile() {
	PROFILE="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	[ "$PROFILE" = "Classic (R2 + A, B, X, Y)" ] && PROFILE="Classic"
	[ "$PROFILE" = "Action (A, X, Select, R1)" ] && PROFILE="Action"
	
	if [ "$PROFILE" = "Custom" ]; then
		SRC="/mnt/SDCARD/Emu/.emu_setup/n64_controller"
		DST="/mnt/SDCARD/RetroArch/.retroarch/config/remaps"
		LUDI="LudicrousN64 Xtreme Amped"
		PARA="ParaLLEl N64"
		MUPEN="Mupen64Plus GLES2"
		if [ "$CORE" = "km_ludicrousn64_2k22_xtreme_amped" ]; then
			cp -f "${DST}/${LUDI}/${LUDI}.rmp" "${SRC}/Custom.rmp"
		elif [ "$CORE" = "km_parallel_n64_xtreme_amped_turbo" ]; then
			cp -f "${DST}/${PARA}/${PARA}.rmp" "${SRC}/Custom.rmp"
		else # CORE is mupen64plus
			cp -f "${DST}/${MUPEN}/${MUPEN}.rmp" "${SRC}/Custom.rmp"
		fi
	fi
}