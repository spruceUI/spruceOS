#!/bin/sh

messages_file="/var/log/messages"

check_and_connect_wifi() {
	show /mnt/SDCARD/.tmp_update/res/waitingtoconnect.png &                           
	sleep 1                                                                     
	killall show
	ifconfig wlan0 up
	wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
	udhcpc -i wlan0 &
	
	while true; do
		if ifconfig wlan0 | grep -qE "inet |inet6 " || tail -n1 "$messages_file" | grep -q "enter_pressed 0"; then
			break
		fi
		sleep 1
	done	
}

if test -f /mnt/SDCARD/.tmp_update/flags/.save_active; then
	keymon &
    if grep -q 'cheevos_enable = "true"' /mnt/SDCARD/RetroArch/retroarch.cfg; then
		check_and_connect_wifi
    fi
    /mnt/SDCARD/.tmp_update/flags/.lastgame &> /dev/null
    /mnt/SDCARD/.tmp_update/scripts/select.sh &> /dev/null
fi
