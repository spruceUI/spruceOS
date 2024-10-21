#!/bin/sh

# print minor info text with the value index zero (i.e. "on" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "0" ] ; then
    echo -n "User: root, Password: tina"
    return 0
fi

# print minor info text with the value index one (i.e. "off" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "1" ] ; then
    echo -n "Secure Shell for remote login"
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/SSH/dropbearFunctions.sh

if [ "$1" == "on" ] ; then
    first_time_setup &
elif [ "$1" == "off" ] ; then
    stop_dropbear_process &
fi
