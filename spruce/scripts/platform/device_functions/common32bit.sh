#!/bin/sh

get_python_path() {
    echo "/mnt/SDCARD/spruce/bin/python/bin/python3.10" 
}

get_sftp_service_name() {
    echo "sftp-server"
}

device_init() {
    log_message "No initialization needed for miyoo mini (handled via .tmp_update)" -v   
}

# This doesn't seem right for all platforms, needs review
set_event_arg() {
    log_message "TODO event arg for miyoo mini?" -v
}

set_dark_httpd_dir() {
    DARKHTTPD_DIR=/mnt/SDCARD/spruce/bin/darkhttpd
}

# Why can't these just all come off the path? / Why do they need special LD LIBRARY PATHS?

set_SMB_DIR(){
    SMB_DIR=/mnt/SDCARD/spruce/bin/Samba
}

set_SFTPGO_DIR() {
    SFTPGO_DIR="/mnt/SDCARD/spruce/bin/SFTPGo"
}

set_syncthing_ST_BIN() {
    ST_BIN=$SYNCTHING_DIR/bin/syncthing
}
