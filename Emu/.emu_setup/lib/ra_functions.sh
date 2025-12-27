#!/bin/sh

. /mnt/SDCARD/Emu/.emu_setup/lib/core_mappings.sh
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
	PLATFORM_CFG=$(get_spruce_ra_cfg_location)
	CURRENT_CFG=$(get_ra_cfg_location)

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
	if [ "$auto_load" = "True" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "true"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	elif [ "$auto_load" = "False" ]; then
		TMP_CFG="$(mktemp)"
	    sed 's|^savestate_auto_load.*|savestate_auto_load = "false"|' "$PLATFORM_CFG" > "$TMP_CFG"
		mv "$TMP_CFG" "$PLATFORM_CFG"
	fi

	# Set hotkey enable button based on spruceUI config
	case "$BRAND" in
		"TrimUI")
			hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyTrimUI.selected' "Menu")"
			;;
		"Miyoo")
			hotkey_enable="$(get_config_value '.menuOptions."Emulator Settings".raHotkeyMiyoo.selected' "Select")"
			;;
	esac
	log_message "ra hotkey enable button is $hotkey_enable" -v
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
	# copy platform-specific RA config into place where RA wants it to be
	cp -f "$PLATFORM_CFG" "$CURRENT_CFG"
}

backup_ra_config() {
	# copy any changes to retroarch.cfg made during RA runtime back to platform-specific config
	use_igm="$(get_config_value '.menuOptions."Emulator Settings".raInGameMenu.selected' "True")"
	PLATFORM_CFG=$(get_spruce_ra_cfg_location)
	CURRENT_CFG=$(get_ra_cfg_location)
	[ -e "$CURRENT_CFG" ] && cp -f "$CURRENT_CFG" "$PLATFORM_CFG"
}

run_retroarch() {
	

	prepare_ra_config 2>/dev/null

	use_igm="$(get_config_value '.menuOptions."Emulator Settings".raInGameMenu.selected' "True")"

	RA_BIN=$(setup_for_retroarch_and_get_bin_location)
	RA_DIR="/mnt/SDCARD/RetroArch"
	cd "$RA_DIR"

	if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
		export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
	else
		export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
	fi

	pin_to_dedicated_cores "$RA_BIN"

	ra_start_setup_saves_and_states_for_core_differences

	#Swap below if debugging new cores
	#HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v --log-file /mnt/SDCARD/Saves/retroarch.log -L "$CORE_PATH" "$ROM_FILE"
	HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$CORE_PATH" "$ROM_FILE"

	backup_ra_config 2>/dev/null
	
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
    log_message "Caching core filename for ROM '$ROM_FILE': '$core'"

    echo "$core" > "$cache_file"
}


get_cached_core_path() {
	# Get only the basename of the ROM file
    rom_basename=$(basename "$ROM_FILE")

    cache_file="/mnt/SDCARD/Saves/spruce/last_core_run/${EMU_NAME}/${rom_basename}"

    if [ -f "$cache_file" ]; then
        cat "$cache_file"
    else
		log_message "No cached core found for ROM '$ROM_FILE'. $cache_file does not exist."
        echo "$CORE_PATH"
    fi
}

handle_changed_core() {
	KEEP_SAVES_BETWEEN_CORES="$(get_config_value '.menuOptions."Emulator Settings".keepSavesBetweenCores.selected' "False")"
	if [ "$KEEP_SAVES_BETWEEN_CORES" = "True" ]; then
		log_message "Syncing saves between cores as per user setting."
		cached_core_folder="$1"
		current_core_folder="$2"

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

    SUFFIX="64"
    [ "$PLATFORM_ARCHITECTURE" = "armhf" ] && SUFFIX="32"

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
		mkdir -p "$BASE/$CORE-$SUFFIX"
        umount "$BASE/$CORE"
    done
}

load_n64_controller_profile() {
	profile="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
	case "$profile" in
		*"Classic"*) profile_name="Classic" ;;
		*"Action"*) profile_name="Action" ;;
		*"Custom"*) return 0 ;;	# don't overwrite the remap if Custom is selected
		*) return 0 ;; # exit early if jq fails or config is broken
	esac

	SRC="/mnt/SDCARD/Emu/.emu_setup/n64_controller"
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

	REMAP_BACKUP="/mnt/SDCARD/Emu/.emu_setup/n64_controller/Custom.rmp"
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
