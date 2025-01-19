#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
    SFTPGO_DIR="/mnt/SDCARD/spruce/bin/SFTPGo"
else
    SFTPGO_DIR="/mnt/SDCARD/spruce/bin64/SFTPGo"
fi

start_sftpgo_process() {
    log_message "Starting SFTPGO..."
    nice -2 $SFTPGO_DIR/sftpgo/sftpgo serve -c $SFTPGO_DIR/sftpgo/ > /dev/null &
    log_message "SFTPGO started with PID $!";
}

stop_sftpgo_process() {
    kill -9 $(pidof sftpgo)
    log_message "SFTPGO process killed";
}