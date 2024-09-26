#!/bin/sh

runifnecessary() {
    a=$(ps | grep $1 | grep -v grep)
    if [ "$a" == "" ]; then
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

    # Check for the themeChanged flag
    if [ -f /mnt/SDCARD/.tmp_update/flags/themeChanged.lock ]; then
        /mnt/SDCARD/App/IconFresh/iconfresh.sh --silent
        rm /mnt/SDCARD/.tmp_update/flags/themeChanged.lock
    fi

    ./MainUI &> /dev/null

    # remove in menu flag
    rm /mnt/SDCARD/.tmp_update/flags/in_menu.lock

    if [ -f /tmp/.cmdenc ]; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ]; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh >/mnt/SDCARD/.tmp_update/flags/.lastgame
        /tmp/cmd_to_run.sh &>/dev/null
        rm /tmp/cmd_to_run.sh

        # reset CPU/GPU/RAM settings to defaults in case an emulator changes anything
        echo 1 > /sys/devices/system/cpu/cpu2/online
        echo 1 > /sys/devices/system/cpu/cpu3/online
        echo conservative > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
        echo 30 > /sys/devices/system/cpu/cpufreq/conservative/down_threshold
        echo 70 > /sys/devices/system/cpu/cpufreq/conservative/up_threshold
        echo 3 > /sys/devices/system/cpu/cpufreq/conservative/freq_step
        echo 1 > /sys/devices/system/cpu/cpufreq/conservative/sampling_down_factor
        echo 400000 > /sys/devices/system/cpu/cpufreq/conservative/sampling_rate
    	echo 200000 > /sys/devices/system/cpu/cpufreq/conservative/sampling_rate_min
        echo 480000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

        # sleep 1

        # show closing screen
        /mnt/SDCARD/.tmp_update/scripts/select.sh &>/dev/null
    fi
done
