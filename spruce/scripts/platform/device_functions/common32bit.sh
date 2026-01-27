#!/bin/sh

get_python_path() {
    echo "/mnt/SDCARD/spruce/bin/python/bin/python3.10" 
}

get_sftp_service_name() {
    echo "sftp-server"
}

get_ssh_service_name() {
    echo "dropbearmulti"
}

device_init() {
    log_message "No initialization needed for miyoo mini (handled via .tmp_update)" -v   
}

# This doesn't seem right for all platforms, needs review
set_event_arg_for_idlemon() {
    log_message "TODO event arg for miyoo mini?" -v
}