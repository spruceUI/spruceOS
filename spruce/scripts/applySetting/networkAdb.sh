#!/bin/sh
# changeCmd for the Network ADB setting. PyUI appends the new value as $1.

if [ "$1" = "True" ]; then
    pidof adbd >/dev/null 2>&1 || /mnt/SDCARD/spruce/miyoomini/bin/adbd >/dev/null 2>&1 </dev/null &
else
    killall adbd 2>/dev/null
fi
exit 0
