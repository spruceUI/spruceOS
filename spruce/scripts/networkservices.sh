#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/SSH/dropbearFunctions.sh
. /mnt/SDCARD/spruce/bin/Samba/sambaFunctions.sh
. /mnt/SDCARD/spruce/bin/SFTPGo/sftpgoFunctions.sh
. /mnt/SDCARD/spruce/bin/Syncthing/syncthingFunctions.sh
. /mnt/SDCARD/spruce/bin/darkhttpd/darkhttpdFunctions.sh

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
	if setting_get "dropbear" && ! pgrep "dropbear" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: Dropbear detected not running, starting..."
		start_dropbear_process
	fi

	# SFTPGo check
	if setting_get "sftpgo" && ! pgrep "sftpgo" >/dev/null; then
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
	for service in "sftpgo" "dropbear" "smbd" "syncthing" "darkhttpd"; do
		if pgrep "$service" >/dev/null; then
			case "$service" in
			"sftpgo") stop_sftpgo_process ;;
			"dropbear") stop_dropbear_process ;;
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
