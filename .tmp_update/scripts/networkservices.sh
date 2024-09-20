#!/bin/sh
. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

messages_file="/var/log/messages"

SSH_DIR="/mnt/SDCARD/App/SSH"
SSH_KEYS="$SSH_DIR/sshkeys"
DROPBEAR="$SSH_DIR/bin/dropbear"
SYNCTHING_DIR=/mnt/SDCARD/App/Syncthing

connect_services() {
	
	while true; do
		if ifconfig wlan0 | grep -qE "inet |inet6 "; then
			
			# SFTPGo check
			if grep -q "ON" "/mnt/SDCARD/App/sftpgo/config.json" && ! pgrep "sftpgo" > /dev/null; then
				# Service is enabled but not running, so start it...
				nice -2 /mnt/SDCARD/.tmp_update/sftpgo/sftpgo serve -c /mnt/SDCARD/.tmp_update/sftpgo/ > /dev/null &
			fi

			# SSH check
			if grep -q "ON" "/mnt/SDCARD/App/SSH/config.json" && ! pgrep "dropbear" > /dev/null; then
				# Service is enabled but not running, so start it...
				$DROPBEAR -r "$SSH_KEYS/dropbear_rsa_host_key" -r "$SSH_KEYS/dropbear_dss_host_key" &
			fi
			
			# Syncthing check
			if grep -q "ON" "/mnt/SDCARD/App/Syncthing/config.json" && ! pgrep "syncthing" > /dev/null; then
				# Service is enabled but not running, so start it...
				$SYNCTHING_DIR/bin/syncthing serve --home=$SYNCTHING_DIR/config/ > $SYNCTHING_DIR/serve.log 2>&1 &
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
