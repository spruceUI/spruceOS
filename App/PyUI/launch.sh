#!/bin/sh

if [ -f /mnt/sdcard/App/PyUI/.enabled ]; then
    rm /mnt/SDCARD/App/PyUI/.enabled
    cp -R /mnt/SDCARD/App/PyUI/theme-overrides/MainUI/Themes/* /mnt/SDCARD/Themes/
else
    echo "" > "/mnt/SDCARD/App/PyUI/.enabled"
    cp -R /mnt/SDCARD/App/PyUI/theme-overrides/PyUI/Themes/* /mnt/SDCARD/Themes/
fi

reboot