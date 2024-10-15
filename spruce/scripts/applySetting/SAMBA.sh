#!/bin/sh

# print minor info text with the value index zero (i.e. "on" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "0" ] ; then
    echo -n "u: root, p: tina"
    return 0
fi

# print minor info text with the value index one (i.e. "off" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "1" ] ; then
    echo -n "Network file-sharing."
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/Samba/sambaFunctions.sh

if [ "$1" == "on" ] ; then
    start_samba_process &
elif [ "$1" == "off" ] ; then
    stop_samba_process &
fi
