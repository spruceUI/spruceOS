#!/bin/sh
. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh
. /mnt/SDCARD/App/sftpgo/sftpgoFunctions.sh

WIFI_ON="/mnt/SDCARD/App/sftpgo/imgs/wifiOn.png"
silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1 #run silently via cli arg?

log_message "Starting SFTPGO launch script"

if [ ! -f /mnt/SDCARD/.tmp_update/flags/sftpgo.lock ]; then
    if [ "$silent_mode" -eq 0 ]; then
		show_image "$WIFI_ON"
	fi
	log_message "SFTPGO lock file not found, starting SFTPGO"
    start_sftpgo_process

    log_message "Creating SFTPGO lock file"
    touch /mnt/SDCARD/.tmp_update/flags/sftpgo.lock
    acknowledge
else
    log_message "SFTPGO lock file found, stopping SFTPGO"
    kill -9 $(pidof sftpgo)
    log_message "SFTPGO process killed";

    log_message "Updating config.json to set SFTPGO status to OFF"
    sed -i 's|- On|- Off|' /mnt/SDCARD/App/sftpgo/config.json

    log_message "Removing SFTPGO lock file"
    rm -f /mnt/SDCARD/.tmp_update/flags/sftpgo.lock
fi

log_message "SFTPGO launch script completed"
