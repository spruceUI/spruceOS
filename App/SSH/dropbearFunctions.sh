#!/bin/sh

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

SSH_DIR="/mnt/SDCARD/App/SSH"
SSH_CONFIG_FILE="$SSH_DIR/config.json"

dropbear_check(){
    if [ -f /mnt/SDCARD/.tmp_update/flags/dropbear.lock ]; then
        start_dropbear_process
    else
        sed -i 's|ON|OFF|' $SSH_CONFIG_FILE
    fi
}

start_dropbear_process(){
    log_message "Starting Dropbear..."
    $SSH_DIR/bin/dropbear -r "$SSH_DIR/sshkeys/dropbear_rsa_host_key" -r "$SSH_DIR/sshkeys/dropbear_dss_host_key" &
    sed -i 's|OFF|ON|' "$SSH_CONFIG_FILE"
}