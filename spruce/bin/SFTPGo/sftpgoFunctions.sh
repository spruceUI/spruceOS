#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SFTPGO_DIR="/mnt/SDCARD/spruce/bin/SFTPGo"

start_sftpgo_process() {
    log_message "Starting SFTPGO..."
    nice -2 /mnt/SDCARD/spruce/bin/SFTPGo/sftpgo/sftpgo serve -c /mnt/SDCARD/spruce/bin/SFTPGo/sftpgo/ > /dev/null &
    log_message "SFTPGO started with PID $!";
}

stop_sftpgo_process() {
    kill -9 $(pidof sftpgo)
    log_message "SFTPGO process killed";
}