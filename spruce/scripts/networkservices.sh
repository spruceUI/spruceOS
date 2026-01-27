#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sftpgoFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/darkhttpdFunctions.sh

SFTP_SERVICE_NAME=$(get_sftp_service_name)
SSH_SERVICE_NAME=$(get_ssh_service_name)

samba_enabled="$(get_config_value '.menuOptions."Network Settings".enableSamba.selected' "False")"
ssh_enabled="$(get_config_value '.menuOptions."Network Settings".enableSSH.selected' "False")"
sftpgo_enabled="$(get_config_value '.menuOptions."Network Settings".enableSFTPGo.selected' "False")"
syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"

connect_services() {

	while true; do
		if ifconfig wlan0 | grep -qE "inet |inet6 " && ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
			break
		fi
		sleep 0.5
	done

	# Samba check
	if [ "$samba_enabled" = "True" ] && ! pgrep "smbd" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: Samba detected not running, starting..."
		start_samba_process
	fi

	# SSH check
	if [ "$ssh_enabled" = "True" ] && ! pgrep "$SSH_SERVICE_NAME" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: $SSH_SERVICE_NAME detected not running, starting..."
		start_ssh_process
	fi

	# SFTPGo check
	if [ "$sftpgo_enabled" = "True" ] && ! pgrep "$SFTP_SERVICE_NAME" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: SFTPGo detected not running, starting..."
		start_sftpgo_process
	fi

	# Syncthing check
	if [ "$syncthing_enabled" = "True" ] && ! pgrep "syncthing" >/dev/null; then
		# Flag exists but service is not running, so start it...
		log_message "Network services: Syncthing detected not running, starting..."
		start_syncthing_process
	fi

	# Start Network Services Landing page
	start_darkhttpd_process

}

disconnect_services() {

	log_message "Network services: Stopping all network services..."
	for service in "$SFTP_SERVICE_NAME" "$SSH_SERVICE_NAME" "smbd" "syncthing" "darkhttpd"; do
		if pgrep "$service" >/dev/null; then
			case "$service" in
			"$SFTP_SERVICE_NAME") stop_sftpgo_process ;;
			"$SSH_SERVICE_NAME") stop_ssh_process ;;
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
