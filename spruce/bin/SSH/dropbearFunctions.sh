#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SSH_DIR="/mnt/SDCARD/spruce/bin/SSH"
SSH_KEYS="$SSH_DIR/sshkeys"
DROPBEAR="$SSH_DIR/bin/dropbear"
DROPBEARKEY="$SSH_DIR/bin/dropbearkey"

dropbear_check(){
    if setting_get "dropbear"; then
        start_dropbear_process
    fi
}

first_time_setup(){
    [ ! -d "$SSH_KEYS" ] && mkdir -p "$SSH_KEYS"
    [ ! -f "$SSH_KEYS/dropbear_rsa_host_key" ] && $DROPBEARKEY -t rsa -f "$SSH_KEYS/dropbear_rsa_host_key"
    [ ! -f "$SSH_KEYS/dropbear_dss_host_key" ] && $DROPBEARKEY -t dss -f "$SSH_KEYS/dropbear_dss_host_key"
    start_dropbear_process
}

start_dropbear_process(){
    log_message "Starting Dropbear..."
    $DROPBEAR -r "$SSH_KEYS/dropbear_rsa_host_key" -r "$SSH_KEYS/dropbear_dss_host_key" -c "$SSH_DIR/dropbear-wrapper.sh" &
    flag_add "dropbear"
}

stop_dropbear_process(){
    log_message "Shutting down Dropbear..."
    killall -9 dropbear
    flag_remove "dropbear"
}