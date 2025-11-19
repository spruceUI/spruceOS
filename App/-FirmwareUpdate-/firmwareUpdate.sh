#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

SD_ROOT="/mnt/SDCARD"
FW_DIR="/mnt/SDCARD/spruce/FIRMWARE_UPDATE"

[ "$PLATFORM" = "SmartPro" ] && BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" || BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree.png"

# get the free space on the SD card in MiB
FREE_SPACE="$(df -m /mnt/SDCARD | awk '{print $4}' | tail -n 1)"

NEEDS_UPDATE=true

case "$PLATFORM" in
	"A30" )
		FW_FILE="miyoo282_fw.img"
		CAPACITY="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/capacity)"
		SPACE_NEEDED=48
		VERSION="$(cat /usr/miyoo/version)"
		[ "$VERSION" -ge 20240713100458 ] && NEEDS_UPDATE=false
		;;
	"Flip" )
		FW_FILE="miyoo355_fw.img"
		CAPACITY="$(cat /sys/class/power_supply/battery/capacity)"
		SPACE_NEEDED=384
		VERSION="$(cat /usr/miyoo/version)"
		[ "$VERSION" -ge 20250627233124 ] && NEEDS_UPDATE="false"
		;;
	"Brick" )
		FW_FILE="trimui_tg3040.awimg"
		CAPACITY="$(cat /sys/class/power_supply/axp2202-battery/capacity)"
		SPACE_NEEDED=1280
        current_fw_is="$(compare_current_version_to_version "1.1.0")"
        [ "$current_fw_is" != "older" ] && NEEDS_UPDATE="false"
		;;
	"SmartPro" )
		FW_FILE="trimui_tg5040.awimg"
		CAPACITY="$(cat /sys/class/power_supply/axp2202-battery/capacity)"
		SPACE_NEEDED=1280
        current_fw_is="$(compare_current_version_to_version "1.1.0")"
        [ "$current_fw_is" != "older" ] && NEEDS_UPDATE="false"
		;;
esac

FW_URL="https://github.com/spruceUI/spruceSource/releases/download/firmware/${FW_FILE}.7z"

# Debugging Variables
SKIP_VERSION_CHECK=false
SKIP_APPLY=false

log_message "firmwareUpdate.sh: free space: $FREE_SPACE"
log_message "firmwareUpdate.sh: charging status: $(get_charging_status)"
log_message "firmwareUpdate.sh: current charge percent: $CAPACITY"
log_message "firmwareUpdate.sh: current FW version: $VERSION"

get_charging_status() {
	case "$PLATFORM" in
		"A30" ) cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online ;;
		"Flip" ) cat /sys/class/power_supply/usb/online ;;
		"Brick" ) cat /sys/class/power_supply/axp2202-usb/online ;;
		"SmartPro" ) cat /sys/class/power_supply/axp2202-usb/online ;;
	esac
}

cancel_update() {
	log_message "firmwareUpdate.sh: Firmware update cancelled."
	display -i "$BG_IMAGE" -o -t "Firmware update cancelled."
	if [ -f "$SD_ROOT/$FW_FILE" ]; then
		rm "$SD_ROOT/$FW_FILE"
		log_message "firmwareUpdate.sh: Removing FW image from root of card."
	fi
	exit 1
}

confirm_update() {
	if [ ! -f "$SD_ROOT/$FW_FILE" ]; then
		display -i "$BG_IMAGE" -d 2 -t "Extracting update to root of SD card. Please wait."
		7zr x "$FW_DIR/$FW_FILE.7z" -o"$SD_ROOT/"
	fi
	case "$PLATFORM" in
		"A30") 
			display -i "$BG_IMAGE" -t "Your A30 will now shut down. Please manually power your device back on while plugged in to complete the manufacturer firmware update. Once started, please be patient, as it will take a few minutes. It will power itself down again once complete." -p 140 -o 
			sync
			poweroff
			;;
		"Flip")
			display -i "$BG_IMAGE" -t "Your Flip will now reboot into the OEM firmware update process. Once started, please be patient, as it will take a few minutes. It will restart itself again once complete." -p 140 -o
			sync
			reboot
			;;
		"Brick"|"SmartPro")
			display -i "$BG_IMAGE" -t "Your $PLATFORM will now reboot. Hold the VOLUME DOWN key as it does so in order to initiate the OEM firmware update process. Once started, please be patient, as it will take a few minutes. It will restart itself again once complete." -p 140 -o
			sync
			reboot
			;;
	esac
	flag_add "first_boot_$PLATFORM"

}

check_for_connection() {
    wifi_enabled="$(jq -r '.wifi' "$SYSTEM_JSON")"
    if [ $wifi_enabled -eq 0 ]; then
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Wi-Fi not enabled. You must enable Wi-Fi to download the firmware update."
        exit 1
    fi

    if ! ping -c 3 github.com > /dev/null 2>&1; then
        display -d 3 --icon "/mnt/SDCARD/spruce/imgs/notfound.png" -t "Unable to connect to GitHub repository. Please check your connection and try again."
        exit 1
    fi
    log_message "FirmwareUpdate.sh: Device is online. Proceeding."
}

# Early out if firmware is already up to date
if [ "$SKIP_VERSION_CHECK" = false ] && [ "$NEEDS_UPDATE" = false ]; then
	log_message "firmwareUpdate.sh: Firmware already up to date. Hiding -FirmwareUpdate- App."
	display -i "$BG_IMAGE" -o -t "Firmware is up to date - happy gaming!!!!!!!!!!"
	sed -i 's|"label":|"#label":|' "$CONFIG"
	exit 0
else
	log_message "firmwareUpdate.sh: Firmware requires update. Continuing."
fi

display -i "$BG_IMAGE" -t "A firmware update from the manufacturer is ready for your device. We'll check your device's status and prepare the manufacturer update file. Once set up, the manufacturer firmware updater will install it." -o -p 160

# Do not allow them to update if they don't have enough space to copy and extract the update file
if [ "$FREE_SPACE" -lt "$SPACE_NEEDED" ]; then
	log_message "firmwareUpdate.sh: Not enough free space on card. Aborting."
	display -i "$BG_IMAGE" -o -t "Not enough free space. Please ensure at least $SPACE_NEEDED MiB of space is available on your SD card, then try again."
	exit 1
else
	log_message "firmwareUpdate.sh: SD card contains at least $SPACE_NEEDED MiB free space. Continuing."
fi

# Do not allow them to update if their battery level is low, to help avoid bricking
if [ "$CAPACITY" -lt 10 ]; then
	log_message "firmwareUpdate.sh: Not enough charge on device. Aborting."
	display -i "$BG_IMAGE" -o -t "As a precaution, please charge your $PLATFORM to at least 10% capacity, then try again."
	exit 1
else
	log_message "firmwareUpdate.sh: Device has at least 10% charge. Continuing."
fi

# Check whether they have the update file on their card already
if [ -f "$FW_DIR/$FW_FILE.7z" ]; then
	log_message "firmwareUpdate.sh: FW file already found on device. No need to download."
else
	mkdir -p "$FW_DIR"
	. /mnt/SDCARD/App/-OTA/downloaderFunctions.sh
	display -i "$BG_IMAGE" -o -t "Please wait while we fetch the update from GitHub. Press A to begin download."
	log_message "firmwareUpdate.sh: FW file not found; user notified of download"
	check_for_connection

	TARGET_SIZE_BYTES="$(curl -k -I -L "$FW_URL" 2>/dev/null | grep -i "Content-Length" | tail -n1 | cut -d' ' -f 2 | tr -d '\r\n')"
	TARGET_SIZE_KILO=$((TARGET_SIZE_BYTES / 1024))
	TARGET_SIZE_MEGA=$((TARGET_SIZE_KILO / 1024))
	BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"

	download_progress "$FW_DIR/$FW_FILE" "$TARGET_SIZE_MEGA" "Now downloading $FW_FILE.7z" &
	download_pid=$!
	if ! curl -s -k -L -o "$FW_DIR/$FW_FILE.7z" "$FW_URL"; then
		kill $download_pid
		log_message "FirmwareUpdate.sh: Failed to download $FW_FILE.7z from $FW_URL"
		display -d 3 --icon "$BAD_IMG" -t "Unable to download $FW_FILE.7z from repository. Please try again later."
		exit 1
	fi
	kill $download_pid
fi

# Require them to be plugged into power (requisite for A30 update to even occur).
if [ "$(get_charging_status)" -eq 0 ]; then
	log_message "firmwareUpdate.sh: Device not plugged in. Prompting user to plug in their $PLATFORM."
	while true; do
		display -i "$BG_IMAGE" -t "Please connect your device to a power source to proceed with the update process." --confirm
		if confirm; then
			# Re-evaluate charging status
			if [ "$(get_charging_status)" -eq 1 ]; then
				log_message "firmwareUpdate.sh: Device is now plugged in. Continuing."
				break
			else
				log_message "firmwareUpdate.sh: Device still not plugged in after user pressed A."
				display -i "$BG_IMAGE" -d 3 -t "Did not detect device charging. You must plug in your device before continuing."
			fi
		else
			log_message "firmwareUpdate.sh: User cancelled update while waiting for device to be plugged in."
			cancel_update
		fi
	done
else
	log_message "firmwareUpdate.sh: Device is plugged in at first charging check. Continuing."
fi

# Give them one last warning, and a chance to proceed with or cancel the FW update.
if [ "$(get_charging_status)" -eq 1 ]; then
	log_message "firmwareUpdate.sh: Device is plugged in. Prompting for A to proceed or B to cancel."
	display -i "$BG_IMAGE" -t "WARNING: If unplugged or powered off before the update is complete, your device could become temporarily bricked, requiring you to run the unbricker software." --okay
	if confirm; then
		log_message "firmwareUpdate.sh: A button pressed. Confirming update."
		if [ "$SKIP_APPLY" = false ]; then
			log_message "firmwareUpdate.sh: Confirming update."
			confirm_update
		fi
	else
		log_message "firmwareUpdate.sh: B button pressed. Cancelling update."
		cancel_update
	fi
else
	display -d 3 -i "$BG_IMAGE" -t "Exiting Firmware Update app. Please try again once you have plugged in your $PLATFORM."
	log_message "firmwareUpdate.sh: Device still not plugged in. Aborting."
fi
