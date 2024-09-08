#!/bin/sh

if [ -f /mnt/SDCARD/.tmp_update/flags/sftpgo.lock ]; then
    nice -2 /mnt/SDCARD/.tmp_update/sftpgo/sftpgo serve -c /mnt/SDCARD/.tmp_update/sftpgo/ > /dev/null &
else
    sed -i 's/ON/OFF/' /mnt/SDCARD/App/sftpgo/config.json
fi