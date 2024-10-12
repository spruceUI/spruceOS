#!/bin/sh

# chech flag and print on/off (without newline) as return value

# if no argument supplied, return -1
if [ -z "$1" ] ; then
    return 1
fi

# check file existence for both flag and flag.lock
if [ -f "/mnt/SDCARD/spruce/flags/$1" ] || [ -f "/mnt/SDCARD/spruce/flags/$1.lock" ]; then
    echo -n "on"
else
    echo -n "off"
fi

return 0
