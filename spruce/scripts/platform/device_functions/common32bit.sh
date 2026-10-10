#!/bin/sh

get_python_path() {
    echo "/mnt/SDCARD/spruce/bin/python/bin/python3.10" 
}

get_sftp_service_name() {
    echo "sftpgo"
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

turn_off_screen() {
    log_message "turn_off_screen() not implemented for $PLATFORM ." -v
}

work_led_off() {
    log_message "work_led_off() not implemented for $PLATFORM ." -v
}

work_led_on() {
    log_message "work_led_on() not implemented for $PLATFORM ." -v
}
