#!/bin/sh
if [ "$1" == "1" ] ; then
    if [ -f /mnt/SDCARD/.tmp_update/flags/ledon.lock ]; then
        echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    elif [ -f /mnt/SDCARD/.tmp_update/flags/tlon.lock ]; then
        echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    else
        echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    fi
else
    if [ -f /mnt/SDCARD/.tmp_update/flags/ledon.lock ]; then
        echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    elif [ -f /mnt/SDCARD/.tmp_update/flags/tlon.lock ]; then
        echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    else
        echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    fi
fi