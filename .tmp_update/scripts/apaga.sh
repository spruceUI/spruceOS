echo heartbeat > /sys/devices/platform/sunxi-led/leds/led1/trigger
	alsactl store ###Saves the current sound settings.
	killall -9 main
	killall -9 runtime.sh
	killall -9 principal.sh
	killall -9 MainUI
	
touch  /mnt/SDCARD/.tmp_update/flags/.save_active
show "/mnt/SDCARD/.tmp_update/res/save.png" &
sync
sleep 3
poweroff
