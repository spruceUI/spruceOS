#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

messages_file="/var/log/messages"

check_and_connect_wifi() {
	log_message "Attempting to connect to WiFi"
	show_image "/mnt/SDCARD/.tmp_update/res/waitingtoconnect.png" 1
	
	ifconfig wlan0 up
	wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
	udhcpc -i wlan0 &
	
	while true; do
		if ifconfig wlan0 | grep -qE "inet |inet6 "; then
			log_message "Successfully connected to WiFi"
			break
		elif tail -n1 "$messages_file" | grep -q "enter_pressed 0"; then
			log_message "WiFi connection cancelled by user"
			break
		fi
		sleep 1
	done	
}

if flag_check "save_active"; then
	log_message "Save active flag detected"
	if grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
		log_message "Retro Achievements enabled, checking WiFi connection"
		check_and_connect_wifi
	fi
	# Restart network services
	/mnt/SDCARD/.tmp_update/scripts/networkservices.sh &
	#Set the LED
	if flag_check "ledon"; then
		echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
	else
		echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
	fi
	
	# copy command to cmd_to_run.sh so game switcher can work correctly
	cp "${FLAGS_DIR}/lastgame.lock" /tmp/cmd_to_run.sh

	log_message "load game to play"
	$FLAGS_DIR/lastgame.lock &> /dev/null

	# remove tmp command file after game exit
	# otherwise the game will load again in principle.sh later
	rm -f /tmp/cmd_to_run.sh

	log_message "Running select script"
	#/mnt/SDCARD/spruce/scripts/select.sh &> /dev/null
	
else
	log_message "Save active flag not detected"
fi
