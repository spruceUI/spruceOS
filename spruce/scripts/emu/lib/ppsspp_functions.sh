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
	export HOME=/mnt/SDCARD/Saves
	cd $EMU_DIR

	mkdir -p "$PSP_SS_DIR"
	mkdir -p "$SS_DIR"

	move_screenshots_if_present
	mount --bind "$SS_DIR" "$PSP_SS_DIR"

	export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"
	case "$PLATFORM" in
		"Brick"|"SmartPro")
			PPSSPPSDL="./PPSSPPSDL_TrimUI"
			;;
		"Pixel2")
			enable_digital_to_analog
			PPSSPPSDL="./PPSSPPSDL_Pixel2"
			;;
		*"Anbernic"*)
			PPSSPPSDL="/mnt/vendor/deep/ppsspp/PPSSPPSDL"
			;;
		*)
			PPSSPPSDL="./PPSSPPSDL_${PLATFORM}"
			;;
	esac
	/mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
	"$PPSSPPSDL" "$ROM_FILE" --fullscreen --pause-menu-exit > ${LOG_DIR}/${CORE}-${PLATFORM}.log 2>&1

	umount "$PSP_SS_DIR"
}

load_ppsspp_configs() {
	PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
	cp -f "$PSP_DIR/controls-$PLATFORM.ini" "$PSP_DIR/controls.ini"
	cp -f "$PSP_DIR/ppsspp-$PLATFORM.ini" "$PSP_DIR/ppsspp.ini"

	rac_mode="$(get_config_value '.menuOptions."RetroAchievements Settings".modeToggle.selected' "Auto")"
	rac_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
	# rac_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"
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
	esac
}

save_ppsspp_configs() {
	PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
	cp -f "$PSP_DIR/controls.ini" "$PSP_DIR/controls-$PLATFORM.ini"
	cp -f "$PSP_DIR/ppsspp.ini" "$PSP_DIR/ppsspp-$PLATFORM.ini"
}
