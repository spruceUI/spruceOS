#!/bin/sh

# chech flag and print on/off (without newline) as return value
# this is placed before loading helping functions for fast checking
if [ "$1" == "check" ] ; then
    if [ -f "/mnt/SDCARD/spruce/flags/dropbear.lock" ]; then
        echo -n "on"
    else
        echo -n "off"
    fi
    return 0
fi

# print minor info text with the value index zero (i.e. "on" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "0" ] ; then
    echo -n "User: root, pwd: tina"
    return 0
fi

# print minor info text with the value index one (i.e. "off" value in config file )
# this is placed before loading helping functions for fast checking
if [ "$1" == "1" ] ; then
    echo -n "Secure Shell for remote login"
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/SSH/dropbearFunctions.sh

CONFIG_FILE="/mnt/SDCARD/App/SSH/config.json"
SSH_DIR="/mnt/SDCARD/App/SSH"
SSH_KEYS="$SSH_DIR/sshkeys"
DROPBEAR="$SSH_DIR/bin/dropbear"
DROPBEARKEY="$SSH_DIR/bin/dropbearkey"

if [ "$1" == "on" ] ; then
    [ ! -d "$SSH_KEYS" ] && mkdir -p "$SSH_KEYS"
    [ ! -f "$SSH_KEYS/dropbear_rsa_host_key" ] && $DROPBEARKEY -t rsa -f "$SSH_KEYS/dropbear_rsa_host_key"
    [ ! -f "$SSH_KEYS/dropbear_dss_host_key" ] && $DROPBEARKEY -t dss -f "$SSH_KEYS/dropbear_dss_host_key"
    start_dropbear_process
    flag_add "dropbear"

elif [ "$1" == "off" ] ; then
    killall -9 dropbear
    flag_remove "dropbear"
fi
