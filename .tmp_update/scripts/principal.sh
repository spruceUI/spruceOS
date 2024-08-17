#!/bin/sh

runifnecessary(){
    a=`ps | grep $1 | grep -v grep`
    if [ "$a" == "" ] ; then
        $2 &
    fi
}
rm /mnt/SDCARD/.tmp_update/flags/.save_active
while [ 1 ]; do
    runifnecessary "keymon" ${SYSTEM_PATH}/app/keymon
    cd ${SYSTEM_PATH}/app/
    ./MainUI
    if [ -f /tmp/.cmdenc ] ; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ] ; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > /mnt/SDCARD/.tmp_update/flags/.lastgame
	/tmp/cmd_to_run.sh
        rm /tmp/cmd_to_run.sh

    fi
sleep 1
/mnt/SDCARD/.tmp_update/scripts/select.sh

done
