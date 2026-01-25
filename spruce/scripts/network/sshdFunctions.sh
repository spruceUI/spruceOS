#!/bin/sh

start_sshd_process() {
    log_message "Starting sshd..."
    systemctl start sshd
    flag_add "sshd"
}

stop_sshd_process() {
    log_message "Shutting down sshd..."
    systemctl stop sshd
    flag_remove "sshd"
}
