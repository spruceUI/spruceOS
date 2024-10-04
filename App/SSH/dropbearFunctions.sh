#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SSH_DIR="/mnt/SDCARD/App/SSH"
SSH_CONFIG_FILE="$SSH_DIR/config.json"

dropbear_check(){
    if flag_check "dropbear"; then
        start_dropbear_process
    else
        sed -i 's|- On|- Off|' $SSH_CONFIG_FILE
    fi
}

start_dropbear_process(){
    log_message "Starting Dropbear..."
    $SSH_DIR/bin/dropbear -r "$SSH_DIR/sshkeys/dropbear_rsa_host_key" -r "$SSH_DIR/sshkeys/dropbear_dss_host_key" &
    sed -i 's|- Off|- On|' "$SSH_CONFIG_FILE"
    sed -i 's|"#label"|"label"|' "$SSH_CONFIG_FILE"
}