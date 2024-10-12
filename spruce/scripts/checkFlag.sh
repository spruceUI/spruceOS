#!/bin/sh

# chech flag and print on/off (without newline) as return value

# if no argument supplied, return -1
if [ -z "$1" ] ; then
    return 1
fi

# check file existance
if [ -f "/mnt/SDCARD/spruce/flags/$1" ]; then
    echo -n "on"
else
    echo -n "off"
fi

return 0
