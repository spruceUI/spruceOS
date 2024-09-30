#!/bin/sh

# Source the helper functions
. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh

runifnecessary() {
    a=$(ps | grep $1 | grep -v grep)
    if [ "$a" == "" ]; then
        $2 &
    fi
}

flag_remove "save_active"
while [ 1 ]; do
    # create in menu flag
    flag_add "in_menu"

    runifnecessary "keymon" ${SYSTEM_PATH}/app/keymon
    # Restart network services with higher priority since booting to menu
    nice -n -15 /mnt/SDCARD/.tmp_update/scripts/networkservices.sh &
    cd ${SYSTEM_PATH}/app/

    # Check for the themeChanged flag
    if flag_check "themeChanged"; then
        /mnt/SDCARD/App/IconFresh/iconfresh.sh --silent
        flag_remove "themeChanged"
    fi

    if flag_check "low_battery"; then
        CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
        display_text -t "Battery has $CAPACITY% left. Charge or shutdown your device." -c dbcda7 --okay
        flag_remove "low_battery"
    fi

    ./MainUI &> /dev/null

    # remove in menu flag
    flag_remove "in_menu"

    if [ -f /tmp/.cmdenc ]; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ]; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > "$FLAGS_DIR/lastgame.lock"
        /tmp/cmd_to_run.sh &>/dev/null
        rm /tmp/cmd_to_run.sh

        # some emulators may use 2 or more cores
        # therefore after closing an emulator
        # we need to turn off other cores except cpu0+1
        echo 1 >/sys/devices/system/cpu/cpu0/online
        echo 1 >/sys/devices/system/cpu/cpu1/online
        echo 0 >/sys/devices/system/cpu/cpu2/online
        echo 0 >/sys/devices/system/cpu/cpu3/online

        # sleep 1

        # show closing screen
        /mnt/SDCARD/.tmp_update/scripts/select.sh &>/dev/null
    fi
done
