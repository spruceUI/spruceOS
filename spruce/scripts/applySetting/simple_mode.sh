#!/bin/sh

ARGUMENT="$1"

check_and_hide_app() {
	SHOWHIDE="/mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh"
	APP_DIR="/mnt/SDCARD/App"
	APP="$1"
	CONFIG="${APP_DIR}/${APP}/config.json"
	[ "$("$SHOWHIDE" check "$CONFIG")" = "on" ] && "$SHOWHIDE" hide "$CONFIG"
}

if [ $ARGUMENT = "apply"]; then

	# remove all X button menu items except aleatorio.sh
	cd /mnt/SDCARD/Emu
	for dir in ./*; do
		if [ -f "${dir}/config.json" ] && [ -f "${dir}/config.json.simple"]; then
			mv "${dir}/config.json" "${dir}/config.json.original"
			cp -f "${dir}/config.json.simple" "${dir}/config.json"
		fi
	done

	# hide majority of apps
	check_and_hide_app "-FirmwareUpdate-"
	check_and_hide_app "-OTA"
	check_and_hide_app "-Updater"
	check_and_hide_app "AdvancedSettings"
	check_and_hide_app "BootLogo"
	check_and_hide_app "FileManagement"
	check_and_hide_app "MiyooGamelist"
	check_and_hide_app "RetroArch"
	check_and_hide_app "ShowOutputTest"
	check_and_hide_app "spruceBackup"
	check_and_hide_app "ThemePacker"

else # ARGUMENT is remove

	# re-enable X menu items
	cd /mnt/SDCARD/Emu
	for dir in ./*; do
		if [ -f "${dir}/config.json.original" ]; then
			[ -f "${dir}/config.json" ] && rm -f "${dir}/config.json"
			mv "${dir}/config.json.original" "${dir}/config.json"
		fi
	done

fi