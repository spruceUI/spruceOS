#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/Syncthing/syncthingFunctions.sh

FLAGS_DIR="/mnt/SDCARD/spruce/flags"
messages_file="/var/log/messages"

set_performance
log_message "Save active flag detected"

wifi_needed=false
syncthing_enabled=false

if grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
	log_message "Retro Achievements enabled, WiFi connection needed"
	wifi_needed=true
fi

if flag_check "syncthing"; then
	log_message "Syncthing is enabled, WiFi connection needed"
	wifi_needed=true
	syncthing_enabled=true
fi

if $syncthing_enabled; then
	if check_and_connect_wifi; then
		start_syncthing_process
		/mnt/SDCARD/App/Syncthing/syncthing_sync_check.sh --startup
		flag_add "syncthing_startup_synced"
	else
		log_message "Failed to connect to WiFi, skipping Sync check"
	fi
elif $wifi_needed; then
	check_and_connect_wifi
fi
#Set the LED
if flag_check "ledon"; then
	echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
else
	echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
fi

# copy command to cmd_to_run.sh so game switcher can work correctly
cp "${FLAGS_DIR}/lastgame.lock" /tmp/cmd_to_run.sh

log_message "load game to play"
sleep 5
nice -n -20 $FLAGS_DIR/lastgame.lock &> /dev/null

# remove tmp command file after game exit
# otherwise the game will load again in principle.sh later
rm -f /tmp/cmd_to_run.sh
