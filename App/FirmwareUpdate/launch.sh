#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

CONFIG="/mnt/SDCARD/App/FirmwareUpdate/config.json"

FW_FILE="/mnt/SDCARD/spruce/FIRMWARE_UPDATE/miyoo282_fw.img"

# get the free space on the SD card in MB
FREE_SPACE="$(df -m /mnt/SDCARD | awk '{print $4}' | tail -n 1)"

CHARGING="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/online)"
CAPACITY="$(cat /sys/devices/platform/axp22_board/axp22-supplyer.20/power_supply/battery/capacity)"
VERSION="$(cat /usr/miyoo/version)"

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

	display -t "Moving firmware update file into place."
	cp "$FW_FILE" "/mnt/SDCARD/"
	kill_display

else
	display -d 5 -t "Please plug in your device and allow it to charge above 20%, then try again."
	exit 1
fi
