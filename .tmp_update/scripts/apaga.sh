. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

echo heartbeat > /sys/devices/platform/sunxi-led/leds/led1/trigger
log_message "Set LED1 trigger to heartbeat"
vibrate

alsactl store
log_message "Saved current sound settings"

if flag_check "syncthing"; then
	log_message "Syncthing is enabled, WiFi connection needed"
	if check_and_connect_wifi; then
		/mnt/SDCARD/App/Syncthing/syncthing_sync_check.sh --shutdown
	fi
fi

log_message "Killing processes"
killall -9 main
killall -9 runtime.sh
killall -9 principal.sh
killall -9 MainUI

flag_add "save_active"
log_message "Created save_active flag"

show_image "/mnt/SDCARD/.tmp_update/res/save.png" 3

sync
log_message "Synced file systems"

log_message "Shutting down"
poweroff