#!/bin/sh

# Requires globals:
#   PLATFORM
#   EMU_DIR
#   ROM_FILE
#   LD_LIBRARY_PATH
#   LOG_DIR
#
# Requires functions:
#   log_message
#
# Provides:
#   move_dotconfig_into_place
#   run_ppsspp
#   load_ppsspp_configs
#   save_ppsspp_configs
#   move_screenshots_if_present

SS_DIR="/mnt/SDCARD/Saves/screenshots/PPSSPP"
PSP_SS_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SCREENSHOT"
PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"

move_dotconfig_into_place() {
	if [ -d "/mnt/SDCARD/Emu/.emu_setup/.config" ]; then
		cp -rf "/mnt/SDCARD/Emu/.emu_setup/.config" "/mnt/SDCARD/Saves/.config" && log_message "Copied .config folder into Saves folder."
	else
		log_message "WARNING!!! No .config folder found!"
	fi
}

move_screenshots_if_present() {
	if [ -n "$(ls -A $PSP_SS_DIR/*.png 2>/dev/null)" ]; then
		mv $PSP_SS_DIR/*.png "$SS_DIR" 2>/dev/null
	fi
}

run_ppsspp() {

	load_ppsspp_configs
	configure_retroachievements

	export HOME=/mnt/SDCARD/Saves
	cd $EMU_DIR

	mkdir -p "$PSP_SS_DIR"
	mkdir -p "$SS_DIR"

	move_screenshots_if_present
	mount --bind "$SS_DIR" "$PSP_SS_DIR"

	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"

	# handle lack of analog sticks on Pixel2
	case "$PLATFORM" in
		"Pixel2") enable_digital_to_analog ;;
	esac

	# accommodate both relative and absolute paths for PPSSPP bin location
	case "$PSP_BIN" in
		"/"*) PPSSPPSDL="$PSP_BIN" ;;
		*)    PPSSPPSDL="./$PSP_BIN" ;;
	esac

	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	if [ -z "$ROM_FILE" ]; then
		"$PPSSPPSDL" --fullscreen > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	else
		"$PPSSPPSDL" "$ROM_FILE" --fullscreen --pause-menu-exit > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1
	fi

	umount "$PSP_SS_DIR"
	save_ppsspp_configs
}

configure_retroachievements() {
	rac_mode="$(get_config_value '.menuOptions."RetroAchievements Settings".modeToggle.selected' "Manual")"
	rac_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
	log_message "Cheevos mode is $rac_mode" -v

	case "$rac_mode" in
		"Disabled")
			# disable cheevos but leave everything else alone
			TMP_CFG="$(mktemp)"
			if sed -e "s|^AchievementsEnable.*|AchievementsEnable = False|" "$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		"Softcore")
			TMP_CFG="$(mktemp)"
			if sed \
				-e "s|^AchievementsEnable.*|AchievementsEnable = True|" \
				-e "s|^AchievementsChallengeMode.*|AchievementsChallengeMode = False|" \
				-e "s|^AchievementsUserName.*|AchievementsUserName = \"$rac_user\"|" \
			"$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		"Hardcore")
			TMP_CFG="$(mktemp)"
			if sed \
				-e "s|^AchievementsEnable.*|AchievementsEnable = True|" \
				-e "s|^AchievementsChallengeMode.*|AchievementsChallengeMode = True|" \
				-e "s|^AchievementsUserName.*|AchievementsUserName = \"$rac_user\"|" \
			"$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
				mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
			else
				rm -f "$TMP_CFG"
			fi
			;;
		*) return 0 ;; # case for Auto - do nothing
	esac

	# update auth token if spruce rac username different from what was in ppsspp.ini
	# or just create it if it's missing
	if [ "$rac_mode" = "Softcore" ] || [ "$rac_mode" = "Hardcore" ]; then
		ini_user="$(grep '^AchievementsUserName' "$PSP_DIR/ppsspp.ini" | sed 's/.*= *"\(.*\)".*/\1/')"
		if [ "$ini_user" != "$rac_user" ] || [ ! -f "$PSP_DIR/ppsspp_retroachievements.dat" ]; then
			rac_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"
			/mnt/SDCARD/spruce/scripts/emu/psp_rac_auth.sh "$rac_user" "$rac_pass"
		fi
	fi
}

load_ppsspp_configs() {
	cp -f "$PSP_DIR/controls-$PLATFORM.ini" "$PSP_DIR/controls.ini"
	cp -f "$PSP_DIR/ppsspp-$PLATFORM.ini" "$PSP_DIR/ppsspp.ini"
}

save_ppsspp_configs() {
	cp -f "$PSP_DIR/controls.ini" "$PSP_DIR/controls-$PLATFORM.ini"
	cp -f "$PSP_DIR/ppsspp.ini" "$PSP_DIR/ppsspp-$PLATFORM.ini"
}
