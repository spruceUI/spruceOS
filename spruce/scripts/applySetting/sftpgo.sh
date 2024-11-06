#!/bin/sh

. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

# print minor info text with the value index zero (i.e. "on" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "0" ]; then
    echo -n "User: spruce, Password: happygaming, Port: 8080"
    return 0
fi

# print minor info text with the value index one (i.e. "off" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "1" ]; then
    echo -n "Manage your files wirelessly"
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/SFTPGo/sftpgoFunctions.sh

if [ "$1" == "on" ]; then
    update_setting "sftpgo" "on"
    log_message "Turning on SFTPGO"
    start_sftpgo_process

elif [ "$1" == "off" ]; then
    update_setting "sftpgo" "off"
    stop_sftpgo_process

    log_message "Turning off SFTPGO"
fi
