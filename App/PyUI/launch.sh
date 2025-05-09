#!/bin/sh

if [ -f /mnt/sdcard/App/PyUI/.enabled ]; then
    rm /mnt/SDCARD/App/PyUI/.enabled
    rm -f /mnt/SDCARD/Saves/.disablesprucewifi
    cp -R /mnt/SDCARD/App/PyUI/theme-overrides/MainUI/Themes/* /mnt/SDCARD/Themes/
else
    echo "" > "/mnt/SDCARD/App/PyUI/.enabled"
    # PyUI handles the wifi part
    echo "" > "/mnt/SDCARD/Saves/.disablesprucewifi"
    cp -R /mnt/SDCARD/App/PyUI/theme-overrides/PyUI/Themes/* /mnt/SDCARD/Themes/
fi

reboot