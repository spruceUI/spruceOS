#!/bin/sh

# Principal Script for Miyoo A30
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

flag_remove "save_active"

BOOT_TO="$(setting_get "boot_to")"

if [ "$BOOT_TO" = "Game Switcher" ] ; then
    touch /mnt/SDCARD/spruce/flags/gs.lock
elif [ "$BOOT_TO" = "Splore" ]; then
    log_message "Pico-8 Splore selected as boot action."
    if [ "$ARCH" = "aarch64" ]; then
        PICO8_BINARY="pico8_64"
    else
        PICO8_BINARY="pico8_dyn"
    fi
    if ( [ -f "/mnt/SDCARD/Emu/PICO8/bin/pico8.dat" ] && [ -f "/mnt/SDCARD/Emu/PICO8/bin/$PICO8_BINARY" ] ) || \
        ( [ -f "/mnt/SDCARD/BIOS/pico8.dat" ] && [ -f "/mnt/SDCARD/BIOS/$PICO8_BINARY" ] ); then
        echo "\"/mnt/SDCARD/Emu/.emu_setup/standard_launch.sh\" \"/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore\"" > /tmp/cmd_to_run.sh
    else
        log_message "Pico-8 binaries not found, booting to MainUI instead"
    fi
fi

while [ "$PLATFORM" = "A30" ]; do

    if [ -f /mnt/SDCARD/spruce/flags/gs.lock ] ; then
        log_message "***** GAME SWITCHER: GS enabled and flag file detected! Launching! *****"
        /mnt/SDCARD/spruce/scripts/gameswitcher.sh
    fi

    if [ ! -f /tmp/cmd_to_run.sh ] ; then
        # create in menu flag and remove last played game flag
        flag_remove "lastgame"

        # check if emu visibility needs a refresh, before entering MainUI
        /mnt/SDCARD/spruce/scripts/emufresh_md5_multi.sh

        # Check for the themeChanged flag
        if flag_check "themeChanged"; then
            /mnt/SDCARD/spruce/scripts/iconfresh.sh --silent
            flag_remove "themeChanged"
        fi

        # Check for the low_battery flag
        if flag_check "low_battery"; then
            CAPACITY=$(cat /sys/class/power_supply/battery/capacity)
            display -t "Battery has $CAPACITY% left. Charge or shutdown your device." --okay
            flag_remove "low_battery"
        fi

        /mnt/SDCARD/spruce/scripts/powerdisplay.sh &

        # This is to kill leftover display processes that may be running
        display_kill &

        # make soft link to serial port with original device name, so MainUI can use it to calibrate joystick
        ln -s /dev/ttyS2 /dev/ttyS0

        # send signal USR2 to joystickinput to switch to KEYBOARD MODE
        # this allows joystick to be used as DPAD in MainUI
        killall -q -USR2 joystickinput

        flag_add "in_menu"
        cd ${SYSTEM_PATH}/app/
        ./MainUI &> /dev/null

        # remove soft link
        rm /dev/ttyS0

        # send signal USR1 to joystickinput to switch to ANALOG MODE
        killall -q -USR1 joystickinput

        if flag_check "pre_cmd_unpacking"; then
            display -t "Finishing up unpacking archives.........." -i "/mnt/SDCARD/spruce/imgs/bg_tree.png"
            while [ -f "$FLAGS_DIR/pre_cmd_unpacking.lock" ]; do
                : # null operation (no sleep needed)
            done
        fi

        flag_remove "in_menu"
    fi

    if [ -f /tmp/cmd_to_run.sh ]; then
        set_performance
        chmod a+x /tmp/cmd_to_run.sh
        cp /tmp/cmd_to_run.sh "$FLAGS_DIR/lastgame.lock"
        /tmp/cmd_to_run.sh &>/dev/null
        rm /tmp/cmd_to_run.sh

        # reset CPU settings to defaults in case an emulator changes anything
        scaling_min_freq=1008000 ### default value, may be overridden in specific script
        set_smart
    fi

    # set gs.lock flag if last loaded program is real game and gs.fix flag is set
    if setting_get "runGSOnGameExit" && \
       grep -q /mnt/SDCARD/Emu/*/../.emu_setup/standard_launch.sh "$FLAGS_DIR/lastgame.lock" ; then
        touch /mnt/SDCARD/spruce/flags/gs.lock
    fi
    
    if [ -f /mnt/SDCARD/spruce/flags/credits.lock ] ; then
        /mnt/SDCARD/App/Credits/launch.sh
        rm /mnt/SDCARD/spruce/flags/credits.lock
    fi

    if flag_check "tmp_update_repair_attempted"; then
        flag_remove "tmp_update_repair_attempted"
        log_message ".tmp_update folder repair appears to have been successful. Removing tmp_update_repair_attempted flag."
    fi

done

runifnecessary(){
    a=$(pgrep "$1")
    if [ "$a" = "" ] ; then
        $2 &
    fi
}

while [ "$PLATFORM" = "Brick" ]; do

    tinymix set 9 1
    tinymix set 1 0
    export LD_LIBRARY_PATH=/usr/trimui/lib
    cd /usr/trimui/bin
    runifnecessary "keymon" keymon
    runifnecessary "inputd" trimui_inputd
    runifnecessary "scened" trimui_scened
    runifnecessary "trimui_btmanager" trimui_btmanager
    runifnecessary "hardwareservice" hardwareservice
    premainui.sh
    MainUI
    preload.sh

    if [ -f /tmp/trimui_inputd_restart ] ; then
        #restart before emulator run
        killall -9 trimui_inputd
        sleep 0.2
        runifnecessary "inputd" trimui_inputd
        rm /tmp/trimui_inputd_restart 
    fi                                                                                         
    if [ -f /tmp/cmd_to_run.sh ] ; then

        set_performance
        chmod a+x /tmp/cmd_to_run.sh
        udpbcast -f /tmp/host_msg &
        /tmp/cmd_to_run.sh
        rm /tmp/cmd_to_run.sh
        rm /tmp/host_msg
        killall -9 udpbcast
        # reset CPU settings to defaults in case an emulator changes anything
        scaling_min_freq=1008000 ### default value, may be overridden in specific script
        set_smart
    fi

done

while [ "$PLATFORM" = "Flip" ]; do

    runee=$(/usr/miyoo/bin/jsonval runee)
    
    if [ "$runee" == "1" ] && [ -f /mnt/SDCARD/emulationstation/emulationstation ] && [ -f /mnt/SDCARD/emulationstation/emulationstation.sh ] ; then
        cd /mnt/SDCARD/emulationstation/
        ./emulationstation.sh
        runee=$(/usr/miyoo/bin/jsonval runee)
        echo runee $runee  >> /tmp/runee.log

    elif [ ! -f /tmp/cmd_to_run.sh ] ; then

        # create in menu flag and remove last played game flag
        flag_remove "lastgame"

        # check if emu visibility needs a refresh, before entering MainUI
        /mnt/SDCARD/spruce/scripts/emufresh_md5_multi.sh

        # Check for the themeChanged flag
        if flag_check "themeChanged"; then
            /mnt/SDCARD/spruce/scripts/iconfresh.sh --silent
            flag_remove "themeChanged"
        fi

        flag_add "in_menu"

        export LD_LIBRARY_PATH=/usr/miyoo/lib
        runifnecessary "keymon" /usr/miyoo/bin/keymon
        runifnecessary "miyoo_inputd" /usr/miyoo/bin/miyoo_inputd
        cd /usr/miyoo/bin/
        ./MainUI

        flag_remove "in_menu"

    else
        touch /tmp/miyoo_inputd/enable_turbo_input
        chmod a+x /tmp/cmd_to_run.sh
        /tmp/cmd_to_run.sh
        rm /tmp/cmd_to_run.sh
        rm /tmp/miyoo_inputd/enable_turbo_input
    fi

done


