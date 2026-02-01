#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SSH_DIR="/mnt/SDCARD/spruce/bin/SSH"
SSH_KEYS="/mnt/SDCARD/spruce/etc/ssh/keys"
SSH_SERVICE_NAME=$(get_ssh_service_name)

dropbear_generate_keys() {
    [ ! -d "$SSH_KEYS" ] && mkdir -p "$SSH_KEYS"
    [ ! -f "$SSH_KEYS/dropbear_rsa_host_key" ] && $SSH_DIR/bin/dropbearmulti dropbearkey -t rsa -f "$SSH_KEYS/dropbear_rsa_host_key"
    [ ! -f "$SSH_KEYS/dropbear_dss_host_key" ] && $SSH_DIR/bin/dropbearmulti dropbearkey -t dss -f "$SSH_KEYS/dropbear_dss_host_key"
}

start_ssh_process() {
    log_message "Starting $SSH_SERVICE_NAME..."
    if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
        # sshd on some devices runs on startup. When using dropbearmulti
        # we need to swap to using it (they both occupy port 22)
        systemctl stop sshd
        killall -9 sshd 2>/dev/null
        $SSH_DIR/bin/dropbearmulti dropbear -r "$SSH_KEYS/dropbear_rsa_host_key" -r "$SSH_KEYS/dropbear_dss_host_key" -c "$SSH_DIR/dropbear-wrapper.sh" &
    else # sshd
        systemctl start sshd
    fi
}

stop_ssh_process() {
    log_message "Shutting down $SSH_SERVICE_NAME..."
    if [ "$SSH_SERVICE_NAME" = "dropbearmulti" ]; then
        killall -9 dropbearmulti
    else # sshd
        systemctl stop sshd
    fi
}
