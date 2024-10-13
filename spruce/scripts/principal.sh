#!/bin/sh

# Principal Script for Miyoo Mini
# 
# This script serves as the main control loop for the system. It operates as follows:
# 
# Initializes by ensuring keymon is running
# Enters an infinite loop that:
#    a. Checks for and handles game switching if necessary
#    b. If not switching games, it runs the main UI
#    c. After UI closes, it either:
#       - Loads and runs a game
#       - Or executes a custom command
# Then the loop repeats, returning to the main UI
#
# Throughout this process, it monitors various system flags and 
# responds accordingly, managing the overall system state.

# Source the helper functions
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

runifnecessary() {
    a=$(ps | grep $1 | grep -v grep)
    if [ "$a" == "" ]; then
        $2 &
    fi
}

# ensure keymon is running first
runifnecessary "keymon" ${SYSTEM_PATH}/app/keymon

flag_remove "save_active"

if [ -f /mnt/SDCARD/spruce/flags/gs.boot ] || \
   [ -f /mnt/SDCARD/spruce/flags/gs.lock ] ; then
    log_message "***** GAME SWITCHER: flag file detected! Launching! *****"
    /mnt/SDCARD/.tmp_update/scripts/gameswitcher.sh
fi

while [ 1 ]; do

    if [ ! -f /tmp/cmd_to_run.sh ] ; then
        # create in menu flag
        flag_add "in_menu"

        runifnecessary "keymon" ${SYSTEM_PATH}/app/keymon
        # Restart network services with higher priority since booting to menu
        nice -n -15 /mnt/SDCARD/.tmp_update/scripts/networkservices.sh &
        cd ${SYSTEM_PATH}/app/

        # Check for the themeChanged flag
        if flag_check "themeChanged"; then
            /mnt/SDCARD/spruce/scripts/iconfresh.sh --silent
            flag_remove "themeChanged"
        fi

        if flag_check "low_battery"; then
            CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
            display -t "Battery has $CAPACITY% left. Charge or shutdown your device." -c dbcda7 --okay
            flag_remove "low_battery"
        fi

        /mnt/SDCARD/.tmp_update/scripts/powerdisplay.sh

        # This is to kill leftover display and show processes that may be running
        display_kill
        kill_images

        ./MainUI &> /dev/null
        # remove in menu flag
        flag_remove "in_menu"
    fi

    if [ -f /tmp/.cmdenc ]; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ]; then
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > "$FLAGS_DIR/lastgame.lock"
        /tmp/cmd_to_run.sh &>/dev/null
        rm /tmp/cmd_to_run.sh

        # reset CPU/GPU/RAM settings to defaults in case an emulator changes anything
        set_smart

        #/mnt/SDCARD/spruce/scripts/select.sh &>/dev/null
    fi

    if [ -f /mnt/SDCARD/spruce/flags/gs.lock ] || \
       [ -f /mnt/SDCARD/spruce/flags/gs.fix ] ; then
        log_message "***** GAME SWITCHER: flag file detected! Launching! *****"
        /mnt/SDCARD/.tmp_update/scripts/gameswitcher.sh
    fi
        
done
