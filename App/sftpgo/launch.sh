#!/bin/sh

if [ ! -f /mnt/SDCARD/.tmp_update/flags/sftpgo.lock ]; then
    nice -2 /mnt/SDCARD/.tmp_update/sftpgo/sftpgo serve -c /mnt/SDCARD/.tmp_update/sftpgo/ > /dev/null &
    sed -i 's/OFF/ON/' /mnt/SDCARD/App/sftpgo/config.json
    touch /mnt/SDCARD/.tmp_update/flags/sftpgo.lock
else
    kill -9 $(pidof sftpgo)
    sed -i 's/ON/OFF/' /mnt/SDCARD/App/sftpgo/config.json
    rm -f /mnt/SDCARD/.tmp_update/flags/sftpgo.lock
fi