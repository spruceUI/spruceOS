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
		if [ -f "${dir}/config.json" ] && [ -f "${dir}/config.json.simple"]; then
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


##### MAIN EXECUTION #####

if [ $ARGUMENT = "apply"]; then

	# apply simple_mode flag
	flag_add "simple_mode"

	# remove all X button menu items except aleatorio.sh
	simplify_x_menus

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

	# spruceRestore, BoxartScraper and RTC apps unhandled - these will respect how the setting-up user sets them

else ##### ARGUMENT is "remove"

	# remove simple_mode flag
	flag_remove "simple_mode"

	# re-enable X menu items
	restore_x_menus

	# reveal RA app because there's no manual toggle for it for them to reveal it themselves
	check_and_reveal_app "RetroArch"

	# don't mess with any other app visibility... we don't know what they had visible before they turned on simple mode.



fi