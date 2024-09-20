#!/bin/sh
. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

messages_file="/var/log/messages"

connect_services() {
	
	while true; do
		if ifconfig wlan0 | grep -qE "inet |inet6 "; then
			
			# SFTPGo check
			if { [ -f "/mnt/SDCARD/App/sftpgo/config.json" ] && grep -q "ON" "/mnt/SDCARD/App/sftpgo/config.json"; }; then
			  /mnt/SDCARD/App/sftpgo/launch_silent.sh # Run once to toggle the menu item to OFF
			  /mnt/SDCARD/App/sftpgo/launch_silent.sh & # Start service
			fi

			# SSH check
			if { [ -f "/mnt/SDCARD/App/SSH/config.json" ] && grep -q "ON" "/mnt/SDCARD/App/SSH/config.json"; }; then
			  /mnt/SDCARD/App/SSH/launch_silent.sh  # Run once to toggle the menu item to OFF
			  /mnt/SDCARD/App/SSH/launch_silent.sh & # Start service
			fi

			# Syncthing check
			if { [ -f "/mnt/SDCARD/App/Syncthing/config.json" ] && grep -q "ON" "/mnt/SDCARD/App/Syncthing/config.json"; }; then
			  /mnt/SDCARD/App/Syncthing/launch_silent.sh   # Run once to toggle the menu item to OFF
			  /mnt/SDCARD/App/Syncthing/launch_silent.sh & # Start service
			fi
			
			break
		fi
		sleep 1
	done
	
}

# Attempt to bring up the network services if WIFI is system enabled
wifi=$(grep '"wifi"' /config/system.json | awk -F ':' '{print $2}' | tr -d ' ,')
if [ "$wifi" -eq 1 ]; then
	if ! ifconfig wlan0 | grep -qE "inet |inet6 "; then
		ifconfig wlan0 up
		wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
		udhcpc -i wlan0 &
	fi
	connect_services
fi
