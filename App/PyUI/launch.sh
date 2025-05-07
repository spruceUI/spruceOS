#!/bin/sh

if [ -f /mnt/sdcard/App/PyUI/.enabled ]; then
    rm /mnt/SDCARD/App/PyUI/.enabled
else
    echo "" > "/mnt/SDCARD/App/PyUI/.enabled"
fi

reboot