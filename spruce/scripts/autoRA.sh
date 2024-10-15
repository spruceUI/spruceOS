#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

messages_file="/var/log/messages"

if flag_check "save_active"; then
	log_message "Save active flag detected"
	if grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
		log_message "Retro Achievements enabled, checking WiFi connection"
		check_and_connect_wifi
	fi
	# Restart network services
	/mnt/SDCARD/.tmp_update/scripts/networkservices.sh &
	
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
