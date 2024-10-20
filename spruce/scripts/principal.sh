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

flag_remove "save_active"

if [ -f /mnt/SDCARD/spruce/flags/gs.boot ] ; then
    touch /mnt/SDCARD/spruce/flags/gs.lock
fi

while [ 1 ]; do

    if [ -f /mnt/SDCARD/spruce/flags/gs.lock ] ; then
        log_message "***** GAME SWITCHER: flag file detected! Launching! *****"
        /mnt/SDCARD/.tmp_update/scripts/gameswitcher.sh
    fi

    if [ ! -f /tmp/cmd_to_run.sh ] ; then
        # create in menu flag
        flag_add "in_menu"

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

        /mnt/SDCARD/spruce/scripts/powerdisplay.sh

        # This is to kill leftover display and show processes that may be running
        display_kill
        kill_images
		
        # check if emu visibility needs a refresh, before entering MainUI
        /mnt/SDCARD/spruce/scripts/emufresh_md5_multi.sh

        ./MainUI &> /dev/null
        # remove in menu flag
        flag_remove "in_menu"
    fi

    if [ -f /tmp/.cmdenc ]; then
        /root/gameloader

    elif [ -f /tmp/cmd_to_run.sh ]; then
        set_performance &
        chmod a+x /tmp/cmd_to_run.sh
        cat /tmp/cmd_to_run.sh > "$FLAGS_DIR/lastgame.lock"
        /tmp/cmd_to_run.sh &>/dev/null
        rm /tmp/cmd_to_run.sh

        # reset CPU settings to defaults in case an emulator changes anything
        set_smart &
    fi

    # set gs.lock flag if last loaded program is real game and gs.fix flag is set
    if [ -f /mnt/SDCARD/spruce/flags/gs.fix ] && \
        grep -q '/mnt/SDCARD/Emu' "$FLAGS_DIR/lastgame.lock" ; then
        touch /mnt/SDCARD/spruce/flags/gs.lock
    fi

    if [ -f /mnt/SDCARD/spruce/flags/credits.lock ] ; then
        /mnt/SDCARD/App/Credits/launch.sh
        rm /mnt/SDCARD/spruce/flags/credits.lock
    fi
    
done
