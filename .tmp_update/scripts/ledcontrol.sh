#!/bin/sh

led_menu_check() {
    while [ 1 ] ; do
        a=`ps | grep launch.sh | grep -v grep`
        if [ "$a" ] ; then
            /mnt/SDCARD/.tmp_update/scripts/ledselection.sh 0
        else
            /mnt/SDCARD/.tmp_update/scripts/ledselection.sh 1
        fi
        sleep 5
    done
}

led_menu_check &