#!/bin/sh

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

WIFI_ON="/mnt/SDCARD/App/sftpgo/imgs/wifiOn.png"

log_message "Starting SFTPGO launch script"

if [ ! -f /mnt/SDCARD/.tmp_update/flags/sftpgo.lock ]; then
    #show_image "$WIFI_ON"
    log_message "SFTPGO lock file not found, starting SFTPGO"
    nice -2 /mnt/SDCARD/.tmp_update/sftpgo/sftpgo serve -c /mnt/SDCARD/.tmp_update/sftpgo/ > /dev/null &
    log_message "SFTPGO started with PID $!";

    log_message "Updating config.json to set SFTPGO status to ON"
    sed -i 's/OFF/ON/' /mnt/SDCARD/App/sftpgo/config.json

    log_message "Creating SFTPGO lock file"
    touch /mnt/SDCARD/.tmp_update/flags/sftpgo.lock
    acknowledge
else
    log_message "SFTPGO lock file found, stopping SFTPGO"
    kill -9 $(pidof sftpgo)
    log_message "SFTPGO process killed";

    log_message "Updating config.json to set SFTPGO status to OFF"
    sed -i 's/ON/OFF/' /mnt/SDCARD/App/sftpgo/config.json

    log_message "Removing SFTPGO lock file"
    rm -f /mnt/SDCARD/.tmp_update/flags/sftpgo.lock
fi

log_message "SFTPGO launch script completed"