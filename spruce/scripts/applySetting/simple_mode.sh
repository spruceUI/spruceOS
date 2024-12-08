#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ARGUMENT="$1" ### "apply" or "remove"
APP_DIR="/mnt/SDCARD/App"
EMU_DIR="/mnt/SDCARD/Emu"
SHOWHIDE="/mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh"

check_and_hide_app() {
	APP="$1"
	CONFIG="${APP_DIR}/${APP}/config.json"
	[ "$("$SHOWHIDE" check "$CONFIG")" = "on" ] && "$SHOWHIDE" hide "$CONFIG"
}

check_and_reveal_app() {
	APP="$1"
	CONFIG="${APP_DIR}/${APP}/config.json"
	[ "$("$SHOWHIDE" check "$CONFIG")" != "on" ] && "$SHOWHIDE" show "$CONFIG"
}

simplify_x_menus() {
	cd "$EMU_DIR"
	for dir in ./*; do
		if [ -f "${dir}/config.json" ] && [ -f "${dir}/config.json.simple" ]; then
			mv "${dir}/config.json" "${dir}/config.json.original"
			cp -f "${dir}/config.json.simple" "${dir}/config.json"
		fi
	done
}

restore_x_menus() {
	cd "$EMU_DIR"
	for dir in ./*; do
		if [ -f "${dir}/config.json.original" ]; then
			[ -f "${dir}/config.json" ] && rm -f "${dir}/config.json"
			mv "${dir}/config.json.original" "${dir}/config.json"
		fi
	done
}

sync_simple_json_from_original() {
	cd "$EMU_DIR"
	for dir in ./*; do
		if [ -f "${dir}/config.json.original" ] \
		&& [ -f "${dir}/config.json" ]; then
			if grep -q "{{" "${dir}/config.json.original"; then
				sed -i 's/^{*$/{{/' "${dir}/config.json"
			else
				sed -i 's/^{{*$/{/' "${dir}/config.json"
			fi
		fi
	done
}

##### MAIN EXECUTION #####

if [ $ARGUMENT = "apply" ]; then

	if flag_check "simple_mode"; then
		log_message "WARNING: simple mode tried to apply when already applied"
		exit 1
	fi

	# apply simple_mode flag
	flag_add "simple_mode"
	log_message "simple_mode activated!"

	# remove all X button menu items except aleatorio.sh
	simplify_x_menus

	# sync emufresh status of both modes' configs
	sync_simple_json_from_original

	# hide majority of apps
	check_and_hide_app "-FirmwareUpdate-"
	check_and_hide_app "-OTA"
	check_and_hide_app "-Updater"
	check_and_hide_app "BootLogo"
	check_and_hide_app "FileManagement"
	check_and_hide_app "MiyooGamelist"
	check_and_hide_app "RetroArch"
	check_and_hide_app "ShowOutputTest"
	check_and_hide_app "spruceBackup"
	check_and_hide_app "ThemePacker"

	# make sure these apps show up
	check_and_reveal_app "AdvancedSettings"
	check_and_reveal_app "RandomGame"
	check_and_reveal_app "spruceHelp"

	# spruceRestore, BoxartScraper and RTC apps unhandled - these will respect how the setting-up user sets them

else ##### ARGUMENT is "remove"

	if ! flag_check "simple_mode"; then
		log_message "WARNING: simple mode tried to remove when not active"
		exit 1
	fi

	# remove simple_mode flag
	flag_remove "simple_mode"
	log_message "simple_mode deactivated!"

	# re-enable X menu items
	restore_x_menus

	# reveal RA app because there's no manual toggle for it for them to reveal it themselves. And Advanced Settings juuuuust in case.
	check_and_reveal_app "AdvancedSettings"
	check_and_reveal_app "RetroArch"

	# don't mess with any other app visibility... we don't know what they had visible before they turned on simple mode.

	killall -9 MainUI
	display -i "/mnt/SDCARD/spruce/imgs/bg_tree.png" -d 2 -t "Exiting Simple Mode!"

fi