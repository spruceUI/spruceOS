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
    ./MainUI  &> /dev/null
    if [ -f /tmp/.cmdenc ] ; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ] ; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > /mnt/SDCARD/.tmp_update/flags/.lastgame
	    /tmp/cmd_to_run.sh  &> /dev/null
        rm /tmp/cmd_to_run.sh

        # some emulators may use 2 or more cores
        # therefore after closing an emulator
        # we need to turn off other cores except cpu0
        echo 1 > /sys/devices/system/cpu/cpu0/online 
        echo 0 > /sys/devices/system/cpu/cpu1/online 
        echo 0 > /sys/devices/system/cpu/cpu2/online 
        echo 0 > /sys/devices/system/cpu/cpu3/online 

        # sleep 1

        # show closing screen 
        /mnt/SDCARD/.tmp_update/scripts/select.sh  &> /dev/null
    fi
done
