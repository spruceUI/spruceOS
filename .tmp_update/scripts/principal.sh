#!/bin/sh

runifnecessary(){
    a=`ps | grep $1 | grep -v grep`
    if [ "$a" == "" ] ; then
        $2 &
    fi
}

rm /mnt/SDCARD/.tmp_update/flags/.save_active
while [ 1 ]; do
    # create in menu flag
    touch /mnt/SDCARD/.tmp_update/flags/in_menu.lock

    runifnecessary "keymon" ${SYSTEM_PATH}/app/keymon
	# Restart network services with higher priority since booting to menu
	nice -n -15 /mnt/SDCARD/.tmp_update/scripts/networkservices.sh &
    cd ${SYSTEM_PATH}/app/
    ./MainUI  &> /dev/null

    # remove in menu flag
    rm /mnt/SDCARD/.tmp_update/flags/in_menu.lock

    if [ -f /tmp/.cmdenc ] ; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ] ; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > /mnt/SDCARD/.tmp_update/flags/.lastgame
	    /tmp/cmd_to_run.sh  &> /dev/null
        rm /tmp/cmd_to_run.sh

        # reset CPU/GPU/RAM settings to defaults in case an emulator changes anything
        /mnt/SDCARD/App/utils/utils "conservative" 4 1344 384 1080 1
        echo 30 > /sys/devices/system/cpu/cpufreq/conservative/down_threshold
        echo 312000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

        # sleep 1

        # show closing screen 
        /mnt/SDCARD/.tmp_update/scripts/select.sh  &> /dev/null
    fi
done