#!/bin/sh

# chech flag and print on/off (without newline) as return value
# this is placed before loading helping functions for fast checking
if [ "$1" == "check" ]; then
    if [ -f "/mnt/SDCARD/spruce/flags/sftpgo.lock" ]; then
        echo -n "on"
    else
        echo -n "off"
    fi
    return 0
fi

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

WIFI_ON="/mnt/SDCARD/App/WifiFileTransfer/imgs/wifiOn.png"

if [ "$1" == "on" ]; then
    start_sftpgo_process

    log_message "Creating SFTPGO flag"
    flag_add "sftpgo"

elif [ "$1" == "off" ]; then
    stop_sftpgo_process

    log_message "Removing SFTPGO flag"
    flag_remove "sftpgo"
fi
