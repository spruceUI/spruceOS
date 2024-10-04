#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SFTPGO_DIR="/mnt/SDCARD/App/sftpgo"
SFTPGO_CONFIG_FILE="$SFTPGO_DIR/config.json"

sftpgo_check(){
    if flag_check "sftpgo"; then
        start_sftpgo_process
    else
        sed -i 's|- On|- Off|' $SFTPGO_CONFIG_FILE
    fi
}

start_sftpgo_process() {
    log_message "Starting SFTPGO..."
    nice -2 /mnt/SDCARD/.tmp_update/sftpgo/sftpgo serve -c /mnt/SDCARD/.tmp_update/sftpgo/ > /dev/null &
    sed -i 's|- Off|- On|' $SFTPGO_CONFIG_FILE
    sed -i 's|"#label"|"label"|' $SFTPGO_CONFIG_FILE
    log_message "SFTPGO started with PID $!";
}