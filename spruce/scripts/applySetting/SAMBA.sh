#!/bin/sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

# print minor info text with the value index zero (i.e. "on" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "0" ]; then
    IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
    if [ -n "$IP" ]; then
        echo -n "\\\\$IP User: spruce, Password: happygaming"
    else
        echo -n "User: spruce, Password: happygaming"
    fi
    return 0
fi

# print minor info text with the value index one (i.e. "off" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "1" ]; then
    echo -n "Network file-sharing."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh

if [ "$1" == "on" ]; then
    update_setting "samba" "on"
    start_samba_process &
elif [ "$1" == "off" ]; then
    update_setting "samba" "off"
    stop_samba_process &
fi
