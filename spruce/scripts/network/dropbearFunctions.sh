#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SSH_DIR="/mnt/SDCARD/spruce/bin/SSH"
SSH_KEYS="/mnt/SDCARD/spruce/etc/ssh/keys"
dropbear_check(){
    if setting_get "dropbear"; then
        start_dropbear_process
    fi
}

first_time_setup(){
    [ ! -d "$SSH_KEYS" ] && mkdir -p "$SSH_KEYS"
    [ ! -f "$SSH_KEYS/dropbear_rsa_host_key" ] && $SSH_DIR/bin/dropbearmulti dropbearkey -t rsa -f "$SSH_KEYS/dropbear_rsa_host_key"
    [ ! -f "$SSH_KEYS/dropbear_dss_host_key" ] && $SSH_DIR/bin/dropbearmulti dropbearkey -t dss -f "$SSH_KEYS/dropbear_dss_host_key"
    start_dropbear_process
}

start_dropbear_process(){
    log_message "Starting Dropbear..."
    $SSH_DIR/bin/dropbearmulti dropbear -r "$SSH_KEYS/dropbear_rsa_host_key" -r "$SSH_KEYS/dropbear_dss_host_key" -c "$SSH_DIR/dropbear-wrapper.sh" &
    flag_add "dropbear"
}

stop_dropbear_process(){
    log_message "Shutting down Dropbear..."
    killall -9 dropbearmulti
    flag_remove "dropbear"
}
