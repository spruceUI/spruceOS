#!/bin/sh

if test -f /mnt/SDCARD/.tmp_update/flags/.save_active; then
    keymon &
    cp /config/system.json /mnt/SDCARD/.tmp_update/scripts/fake_json/system.json.orig
    cp /mnt/SDCARD/.tmp_update/scripts/fake_json/system.json.black /config/system.json
    mv /mnt/SDCARD/Themes/DONTTOUCH/config.json.black /mnt/SDCARD/Themes/DONTTOUCH/config.json
    /mnt/SDCARD/miyoo/app/MainUI &
    sleep 4
    killall -9 MainUI
    cp /mnt/SDCARD/.tmp_update/scripts/fake_json/system.json.orig /config/system.json
    mv /mnt/SDCARD/Themes/DONTTOUCH/config.json /mnt/SDCARD/Themes/DONTTOUCH/config.json.black
    /mnt/SDCARD/.tmp_update/flags/.lastgame
    /mnt/SDCARD/.tmp_update/scripts/select.sh
    return
else
    /mnt/SDCARD/.tmp_update/scripts/principal.sh
fi