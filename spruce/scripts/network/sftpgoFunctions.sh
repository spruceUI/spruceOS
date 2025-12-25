#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_SFTPGO_DIR

start_sftpgo_process() {
    log_message "Starting SFTPGO..."
    nice -2 $SFTPGO_DIR/sftpgo/sftpgo serve -c $SFTPGO_DIR/sftpgo/ > /dev/null &
    log_message "SFTPGO started with PID $!";
}

stop_sftpgo_process() {
    kill -9 $(pidof sftpgo)
    log_message "SFTPGO process killed";
}