#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/dropbearFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sftpgoFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/darkhttpdFunctions.sh

if [ $PLATFORM = "A30" ]; then
	SFTP_SERVICE_NAME=sftp-server 
else
	SFTP_SERVICE_NAME=sftpgo
fi	

connect_services() {

	while true; do
		if ifconfig wlan0 | grep -qE "inet |inet6 " && ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
			break
		fi
		sleep 0.5
	done

	# Samba check
	if setting_get "samba" && ! pgrep "smbd" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: Samba detected not running, starting..."
		start_samba_process
	fi

	# SSH check
	if setting_get "dropbear" && ! pgrep "dropbearmulti" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: Dropbear detected not running, starting..."
		start_dropbear_process
	fi

	# SFTPGo check
	if setting_get "sftpgo" && ! pgrep "$SFTP_SERVICE_NAME" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: SFTPGo detected not running, starting..."
		start_sftpgo_process
	fi

	# Syncthing check
	if setting_get "syncthing" && ! pgrep "syncthing" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: Syncthing detected not running, starting..."
		start_syncthing_process
	fi

	# Start Network Services Landing page
	start_darkhttpd_process

}

disconnect_services() {

	log_message "Network services: Stopping all network services..."
	for service in "$SFTP_SERVICE_NAME" "dropbearmulti" "smbd" "syncthing" "darkhttpd"; do
		if pgrep "$service" >/dev/null; then
			case "$service" in
			"$SFTP_SERVICE_NAME") stop_sftpgo_process ;;
			"dropbearmulti") stop_dropbear_process ;;
			"smbd") stop_samba_process ;;
			"syncthing") stop_syncthing_process ;;
			"darkhttpd") stop_darkhttpd_process ;;
			esac
		fi
	done

}

if [ "$1" = "off" ]; then
	disconnect_services
else
	connect_services
fi
