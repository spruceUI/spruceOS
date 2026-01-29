#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh

start_pyui_message_writer

SD_ROOT="/mnt/SDCARD"
FW_DIR="/mnt/SDCARD/spruce/FIRMWARE_UPDATE"

# get the free space on the SD card in MiB
FREE_SPACE="$(df -m /mnt/SDCARD | awk '{print $4}' | tail -n 1)"

NEEDS_UPDATE=true
case "$PLATFORM" in
	"A30"|"Flip"|"Brick"|"SmartPro"|"SmartProS")
		NEEDS_UPDATE="$(check_if_fw_needs_update)"
		;;
	*)
		log_and_display_message "The firmware updater app does not currently support the ${BRAND} ${PLATFORM}."
		sleep 5
		exit 1
		;;
esac

FW_URL="https://github.com/spruceUI/spruceSource/releases/download/firmware/${FW_FILE}.7z"

# Debugging Variables
SKIP_VERSION_CHECK=false
SKIP_APPLY=false

log_message "firmwareUpdate.sh: current device: $PLATFORM"
log_message "firmwareUpdate.sh: free space: $FREE_SPACE"
log_message "firmwareUpdate.sh: charging status: $(device_get_charging_status)"
log_message "firmwareUpdate.sh: current charge percent: $(device_get_battery_percent)"
log_message "firmwareUpdate.sh: current FW version: $VERSION"

cancel_update() {
	log_and_display_message "Firmware update cancelled."
	sleep 5
	if [ -f "$SD_ROOT/$FW_FILE" ]; then
		rm "$SD_ROOT/$FW_FILE"
		log_message "firmwareUpdate.sh: Removing FW image from root of card."
	fi
	exit 1
}

confirm_update() {
	if [ ! -f "$SD_ROOT/$FW_FILE" ]; then
		log_and_display_message "Extracting update to root of SD card. Please wait."
		sleep 1
		7zr x "$FW_DIR/$FW_FILE.7z" -o"$SD_ROOT/"
	fi
	case "$PLATFORM" in
		"A30") 
			conf_msg="Your A30 will now shut down. Please manually power your device back on while plugged in to complete the manufacturer firmware update. Once started, please be patient, as it will take a few minutes. It will power itself down again once complete."
			;;
		"Flip")
			conf_msg="Your Flip will now reboot into the OEM firmware update process. Once started, please be patient, as it will take a few minutes. It will restart itself again once complete."
			;;
		"Brick"|"SmartPro"*)
			conf_msg="Your $PLATFORM will now reboot. Hold the VOLUME DOWN key as it does so in order to initiate the OEM firmware update process. Once started, please be patient, as it will take a few minutes. It will restart itself again once complete."
			;;
	esac
	conf_msg="$conf_msg Press A to proceed."
	log_and_display_message "$conf_msg"
	sleep 1
	acknowledge
	flag_add "first_boot_$PLATFORM"
	sync
	reboot
}

check_for_connection() {
    wifi_enabled="$(jq -r '.wifi' "$SYSTEM_JSON")"
    if [ $wifi_enabled -eq 0 ]; then
		display_image_and_text "/mnt/SDCARD/spruce/imgs/notfound.png" 25 25 "Wi-Fi not enabled. You must enable Wi-Fi to download the firmware update." 75
		sleep 5
        exit 1
    fi

    if ! ping -c 3 github.com > /dev/null 2>&1; then
		display_image_and_text "/mnt/SDCARD/spruce/imgs/notfound.png" 25 25 "Unable to connect to GitHub repository. Please check your connection and try again." 75
		sleep 5
        exit 1
    fi
    log_message "FirmwareUpdate.sh: Device is online. Proceeding."
}


##### MAIN EXECUTION #####

# Early out if firmware is already up to date
if [ "$SKIP_VERSION_CHECK" = false ] && [ "$NEEDS_UPDATE" = false ]; then
	log_and_display_message "Firmware is up to date - happy gaming!!!!!!!!!!"
	sleep 5
	sed -i 's|"label":|"#label":|' "/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
	exit 0
else
	log_message "firmwareUpdate.sh: Firmware requires update. Continuing."
fi

log_and_display_message "A firmware update from $BRAND is ready for your device. We'll check your device's status and prepare the $BRAND update file. Once set up, the $BRAND firmware updater will install it. Press A to proceed."
sleep 1
acknowledge

# Do not allow them to update if they don't have enough space to copy and extract the update file
if [ "$FREE_SPACE" -lt "$REQ_MB_TO_UPDATE_FW" ]; then
	log_and_display_message "Not enough free space. Please ensure at least $REQ_MB_TO_UPDATE_FW MiB of space is available on your SD card, then try again."
	sleep 5
	exit 1
else
	log_message "firmwareUpdate.sh: SD card contains at least $REQ_MB_TO_UPDATE_FW MiB free space. Continuing."
fi

# Do not allow them to update if their battery level is low, to help avoid bricking
if [ "$(device_get_battery_percent)" -lt 15 ]; then
	log_and_display_message "As a precaution, please charge your $PLATFORM to at least 15% capacity, then try again."
	sleep 5
	exit 1
else
	log_message "firmwareUpdate.sh: Device has at least 10% charge. Continuing."
fi

# Check whether they have the update file on their card already
if [ -f "$FW_DIR/$FW_FILE.7z" ]; then
	log_message "firmwareUpdate.sh: FW file already found on device. No need to download."
else
	mkdir -p "$FW_DIR"
	log_and_display_message "Please wait while we fetch the update from GitHub."
	check_for_connection

	target_size="$(curl -k -I -L "$FW_URL" 2>/dev/null | grep -i "Content-Length" | tail -n1 | cut -d' ' -f 2 | tr -d '\r\n')"

	if ! download_and_display_progress "$FW_URL" "$FW_DIR/$FW_FILE.7z" "$FW_FILE.7z" "$target_size"; then
		exit 1
	fi
fi

# Require them to be plugged into power (requisite for A30 update to even occur).
if [ "$(device_get_charging_status)" = "Discharging" ]; then
	log_message "firmwareUpdate.sh: Device not plugged in. Prompting user to plug in their $PLATFORM."
	while true; do
		log_and_display_message "Please connect your device to a power source to proceed with the update process. Press A to continue, or B to cancel."
		sleep 1
		if confirm; then
			# Re-evaluate charging status
			if [ "$(device_get_charging_status)" != "Discharging" ] || [ "$PLATFORM" != "A30" ] && [ "$(device_get_battery_percent)" -ge 35 ]; then
				log_message "firmwareUpdate.sh: Device is now plugged in, or at least >35% capacity. Continuing."
				break
			else
				log_and_display_message "Did not detect device charging. You must plug in your device before continuing."
				sleep 3
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
if [ "$(device_get_charging_status)" != "Discharging" ] || [ "$PLATFORM" != "A30" ]; then
	log_and_display_message "WARNING: If powered off before the update is complete, your device could become temporarily bricked, requiring you to run the unbricker software. Press A to continue, or B to cancel."
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
	log_and_display_message "Exiting Firmware Update app. Please try again once you have plugged in your $PLATFORM."
	sleep 5
fi
