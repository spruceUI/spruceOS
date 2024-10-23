#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

CONFIG="/mnt/SDCARD/App/-FirmwareUpdate-/config.json"
FW_FILE="/mnt/SDCARD/spruce/FIRMWARE_UPDATE/miyoo282_fw.img"
BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree.png"

# get the free space on the SD card in MiB
FREE_SPACE="$(df -m /mnt/SDCARD | awk '{print $4}' | tail -n 1)"

CHARGING="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online)"
CAPACITY="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/capacity)"
VERSION="$(cat /usr/miyoo/version)"

log_message "firmwareUpdate.sh: free space: $FREE_SPACE"
log_message "firmwareUpdate.sh: charging status: $CHARGING"
log_message "firmwareUpdate.sh: current charge percent: $CAPACITY"
log_message "firmwareUpdate.sh: current FW version: $VERSION"

cancel_update() {
	display -o -t "Firmware update cancelled."
	if [ -f "/mnt/SDCARD/miyoo282_fw.img" ]; then
		rm "/mnt/SDCARD/miyoo282_fw.img"
		log_message "Removing FW image from root of card."
	fi
	exit 1
}

confirm_update() {
	if [ ! -f "/mnt/SDCARD/miyoo282_fw.img" ]; then
		display -i "$BG_IMAGE" -d 2 -t "Moving firmware update file into place."
		cp "$FW_FILE" "/mnt/SDCARD/"
	fi
	display -d 8 -t "Your A30 will now shut down. Please manually power your device back on while plugged in to complete firmware update. Once started, please be patient, as it will take a few minutes. It will power itself down again once complete."
    sed -i 's|"label":|"#label":|' "$CONFIG"
	flag_add "first_boot"
	flag_remove "config_copied"
	sync
	poweroff
}

if [ "$VERSION" -ge 20240713100458 ]; then
	log_message "firmwareUpdate.sh: Firmware already up to date. Hiding -FirmwareUpdate- App."
	display -i "$BG_IMAGE" -o -t "Firmware is up to date - happy gaming!!!!!!!!!!"
    sed -i 's|"label":|"#label":|' "$CONFIG"
	exit 0
else
	log_message "firmwareUpdate.sh: Firmware requires update. Continuing."
fi

if [ "$FREE_SPACE" -lt 64 ]; then
	log_message "firmwareUpdate.sh: Not enough free space on card. Aborting."
	display -i "$BG_IMAGE" -o -t "Not enough free space. Please ensure at least 64 MiB of space is available on your SD card, then try again."
	exit 1
else
	log_message "firmwareUpdate.sh: SD card contains at least 64MiB free space. Continuing."
fi

if [ "$CAPACITY" -lt 10 ]; then
	log_message "firmwareUpdate.sh: Not enough charge on device. Aborting."
	display -i "$BG_IMAGE" -o -t "As a precaution, please charge your A30 to at least 10% capacity, then try again."
	exit 1
else
	log_message "firmwareUpdate.sh: Device has at least 10% charge. Continuing."
fi

if [ "$CHARGING" -eq 0 ]; then
	log_message "firmwareUpdate.sh: Device not plugged in. Prompting user to plug in their A30."
	display -i "$BG_IMAGE" -t "A firmware update is ready for your device. Please connect your device to a power source in order to proceed with the update process."

	# re-evaluate charging status in case they plug it in here.
	CHARGING="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online)"
else
	log_message "firmwareUpdate.sh: Device is plugged in at first charging check. Continuing."
fi

if [ "$CHARGING" -eq 1 ]; then
	log_message "firmwareUpdate.sh: Device is plugged in. Prompting for SELECT to proceed or B to cancel."
	display -i "$BG_IMAGE" -t " The spruce team highly recommends that you proceed with the update; however, please be aware that if interrupted before the update is complete, it could temporarily brick your device, requiring you to run the unbricker software. Press B to cancel the update, or press SELECT to continue."
	B_pressed=0
	SE_pressed=0
	get_event | while read input; do
		case "$input" in 
			*"$B_B 1"*)
				B_pressed=1
				;;
			*"$B_SELECT 1"*)
				SE_pressed=1
				;;
		esac
		if [ "$B_pressed" = 1 ]; then
			killall getevent
			log_message "firmwareUpdate.sh: B button pressed. Cancelling update."
			cancel_update
			break
		elif [ "$SE_pressed" = 1 ]; then
			killall getevent
			log_message "firmwareUpdate.sh: SELECT button pressed. Confirming update."
			confirm_update
			break
		fi
	done
else
	log_message "firmwareUpdate.sh: Device still not plugged in. Aborting."
fi

killall getevent