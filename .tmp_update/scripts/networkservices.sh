#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/SSH/dropbearFunctions.sh
. /mnt/SDCARD/App/sftpgo/sftpgoFunctions.sh
. /mnt/SDCARD/App/Syncthing/syncthingFunctions.sh

connect_services() {
	
	while true; do
		if ifconfig wlan0 | grep -qE "inet |inet6 "; then
			
			# SFTPGo check
			if flag_check "sftpgo" && ! pgrep "sftpgo" > /dev/null; then
				# Flag exists but service is not running, so start it...
				log_message "Network services: SFTPGo detected not running, starting..."
				start_sftpgo_process
			fi

			# SSH check
			if flag_check "dropbear" && ! pgrep "dropbear" > /dev/null; then
				# Flag exists but service is not running, so start it...
				log_message "Network services: Dropbear detected not running, starting..."
				start_dropbear_process
			fi
			
			# Syncthing check
			if flag_check "syncthing" && ! pgrep "syncthing" > /dev/null; then
				# Flag exists but service is not running, so start it...
				log_message "Network services: Syncthing detected not running, starting..."
				start_syncthing_process
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
