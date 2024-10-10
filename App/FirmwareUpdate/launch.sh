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
	display -d 5 -t "Firmware update cancelled."
	if [ -f "/mnt/SDCARD/miyoo282_fw.img" ]; then
		rm "/mnt/SDCARD/miyoo282_fw.img"
		log_message "User cancelled FW update. Removing FW image from root of card."
	fi
	kill -9 "$cancel_pid"
	kill -9 "$confirm_pid"
	exit 1
}

confirm_update() {
	if [ ! -f "/mnt/SDCARD/miyoo282_fw.img" ]; then
		display -t "Moving firmware update file into place."
		cp "$FW_FILE" "/mnt/SDCARD/"
	fi
	display -o -t "Your A30 will now shut down. Please manually power your device back on while plugged in to complete firmware update. Once started, please be patient, as it will take a few minutes. It will power itself down again once complete."
    sed -i 's|"label":|"#label":|' "$CONFIG"
	sync
	poweroff
}

if [ "$VERSION" -ge 20240713100458 ]; then
	display -d 3 -t "Firmware is up to date - happy gaming!!!!!!!!!!"
    sed -i 's|"label":|"#label":|' "$CONFIG"
	exit 0
fi

if [ "$FREE_SPACE" -lt 64 ]; then
	display -d 5 -t "Not enough free space. Please ensure at least 64 MiB of space is available on your SD card, then try again."
	exit 1
fi

if [ "$CHARGING" -eq 1 ] && [ "$CAPACITY" -ge 20 ]; then
	exec_on_hotkey cancel_update "$B_B" &
	cancel_pid="$!"
	exec_on_hotkey confirm_update "$B_Y" "$B_L2" &
	confirm_pid="$!"
	display -t "A firmware update is ready for your device. The spruce team highly recommends that you proceed with the update; however, please be aware that if interrupted before the update is complete, it could temporarily brick your device, requiring you to run the unbricker software. Press B to cancel the update, or press L2+Y to continue."
	kill -9 "$cancel_pid"
	kill -9 "$confirm_pid"
else
	display -d 5 -t "Please plug in your device and allow it to charge above 20%, then try again."
	exit 1
fi
