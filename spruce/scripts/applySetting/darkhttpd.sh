#!/bin/sh

. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

# print minor info text with the value index zero (i.e. "on" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "0" ] ; then
    IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
    if [ -n "$IP" ]; then
        echo -n "IP: $IP"
    else
        echo -n "localhost"
    fi
    return 0
fi

# print minor info text with the value index one (i.e. "off" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "1" ] ; then
    echo -n "Serve Spruce landing page."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/darkhttpdFunctions.sh

if [ "$1" == "on" ] ; then
    update_setting "darkhttpd" "on"
    start_darkhttpd_process &
elif [ "$1" == "off" ] ; then
    update_setting "darkhttpd" "off"
    stop_darkhttpd_process &
fi


$DARKHTTPD=/mnt/SDCARD/spruce/scripts/applySetting/darkhttpd.sh$
<Not_simple>
"" "Enable Web Server" "|" "on|off" "$HELP$ check darkhttpd" "$DARKHTTPD$ _VALUE_" "$DARKHTTPD$ _INDEX_"
@"Serve Spruce landing page"
<Simple>
%"/mnt/SDCARD/spruce/scripts/applySetting/networkServices.sh darkhttpd"