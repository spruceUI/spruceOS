#!/bin/sh
. /mnt/SDCARD/.tmp_update/scripts/globalFunctions.sh

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

if test -f /mnt/SDCARD/.tmp_update/flags/.save_active; then
	log_message "Save active flag detected"
	keymon &
	if grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
		log_message "Retro Acheivements enabled, checking WiFi connection"
		check_and_connect_wifi
	fi
	log_message "Adding last game flag"
	/mnt/SDCARD/.tmp_update/flags/.lastgame &> /dev/null
	log_message "Running select script"
	/mnt/SDCARD/.tmp_update/scripts/select.sh &> /dev/null
else
	log_message "Save active flag not detected"
fi
