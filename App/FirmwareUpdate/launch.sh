#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

CONFIG="/mnt/SDCARD/App/FirmwareUpdate/config.json"
FW_FILE="/mnt/SDCARD/spruce/FIRMWARE_UPDATE/miyoo282_fw.img"

# get the free space on the SD card in MiB
FREE_SPACE="$(df -m /mnt/SDCARD | awk '{print $4}' | tail -n 1)"

CHARGING="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online)"
CAPACITY="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/capacity)"
VERSION="$(cat /usr/miyoo/version)"

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
		display -d 2 -t "Moving firmware update file into place."
		cp "$FW_FILE" "/mnt/SDCARD/"
	fi
	display -d 8 -t "Your A30 will now shut down. Please manually power your device back on while plugged in to complete firmware update. Once started, please be patient, as it will take a few minutes. It will power itself down again once complete."
    sed -i 's|"label":|"#label":|' "$CONFIG"
	flag_add "first_boot"
	sync
	poweroff
}

if [ "$VERSION" -ge 20240713100458 ]; then
	display -o -t "Firmware is up to date - happy gaming!!!!!!!!!!"
    sed -i 's|"label":|"#label":|' "$CONFIG"
	exit 0
fi

if [ "$FREE_SPACE" -lt 64 ]; then
	display -o -t "Not enough free space. Please ensure at least 64 MiB of space is available on your SD card, then try again."
	exit 1
fi

if [ "$CAPACITY" -lt 10 ]; then
	display -o -t "As a precaution, please charge your A30 to at least 10% capacity, then try again."
	exit 1
fi

if [ "$CHARGING" -eq 0 ]; then
	display -o -t "A firmware update is ready for your device. Please connect your device to a power source in order to proceed with the update process."

	# re-evaluate charging status in case they plug it in here.
	CHARGING="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online)"
fi

if [ "$CHARGING" -eq 1 ]; then
	display -t " The spruce team highly recommends that you proceed with the update; however, please be aware that if interrupted before the update is complete, it could temporarily brick your device, requiring you to run the unbricker software. Press B to cancel the update, or press SELECT to continue."
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
			log_message "cancelling update."
			cancel_update
			break
		elif [ "$SE_pressed" = 1 ]; then
			killall getevent
			log_message "confirming update."
			confirm_update
			break
		fi
	done
fi

killall getevent