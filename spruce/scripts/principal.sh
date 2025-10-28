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

runifnecessary(){
    a=$(pgrep "$1")
    if [ "$a" = "" ] ; then
        $2 &
    fi
}

# Source the helper functions
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Set up the boot_to action prior to getting into the principal loop
BOOT_ACTION="$(setting_get "boot_to")"
if ! flag_check "save_active"; then
    case "$BOOT_ACTION" in
        "Random")
            log_message "Booting to random game selection"
            echo "\"/mnt/SDCARD/App/RandomGame/random.sh\"" > /tmp/cmd_to_run.sh
            ;;
        "Switcher")
            touch /mnt/SDCARD/spruce/flags/gs.lock
            ;;
        "Splore")
            log_message "Attempting to boot into Pico-8. Checking for binaries"
            if [ "$ARCH" == "aarch64" ]; then
                PICO8_EXE="pico8_64"
            else
                PICO8_EXE="pico8_dyn"
            fi
            if ( [ -f "/mnt/SDCARD/Emu/PICO8/bin/pico8.dat" ] && [ -f "/mnt/SDCARD/Emu/PICO8/bin/$PICO8_EXE" ] ) || \
                ( [ -f "/mnt/SDCARD/BIOS/pico8.dat" ] && [ -f "/mnt/SDCARD/BIOS/$PICO8_EXE" ] ); then
                echo "\"/mnt/SDCARD/Emu/.emu_setup/standard_launch.sh\" \"/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore\"" > /tmp/cmd_to_run.sh
            else
                log_message "Pico-8 binaries not found, booting to MainUI instead"
            fi
            ;;
    esac
fi

flag_remove "save_active"

while [ 1 ]; do

    if [ -f /mnt/SDCARD/spruce/flags/gs.lock ]; then
        log_message "***** GAME SWITCHER: GS enabled and flag file detected! Launching! *****"
        /mnt/SDCARD/spruce/scripts/gameswitcher.sh
    fi

    if [ -f /mnt/SDCARD/spruce/flags/bitpal.lock ]; then
        /mnt/SDCARD/App/BitPal/bitpal.sh
        rm -f /mnt/SDCARD/spruce/flags/bitpal.lock
    fi

    if [ ! -f /tmp/cmd_to_run.sh ]; then
        # create in menu flag and remove last played game flag
        flag_remove "lastgame"

        # Check for the themeChanged flag
        if flag_check "themeChanged"; then
            /mnt/SDCARD/spruce/scripts/iconfresh.sh --silent
            flag_remove "themeChanged"
        fi

        # Check for the low_battery flag
        if flag_check "low_battery"; then
            CAPACITY=$(cat $BATTERY/capacity)
            display -t "Battery has $CAPACITY% left. Charge or shutdown your device." --okay
            flag_remove "low_battery"
        fi

        # This is to mostly to allow themes to unpack before hitting the menu so they are immediately visible to MainUI
        if flag_check "pre_menu_unpacking"; then
            display -t "Finishing up unpacking archives.........." -i "/mnt/SDCARD/spruce/imgs/bg_tree.png"
            flag_remove "silentUnpacker"
            while [ -f "$FLAGS_DIR/pre_menu_unpacking.lock" ]; do
                : # null operation (no sleep needed)
            done
        fi

        # This is to kill leftover display processes that may be running
        display_kill &

        flag_add "in_menu"

        # Launch (and subsequently close) MainUI with various quirks depending on PLATFORM
        case "$PLATFORM" in
            "A30" )
                # make soft link to serial port with original device name, so MainUI can use it to calibrate joystick
                ln -s /dev/ttyS2 /dev/ttyS0

                # send signal USR2 to joystickinput to switch to KEYBOARD MODE
                # this allows joystick to be used as DPAD in MainUI
                killall -q -USR2 joystickinput

                # send signal USR1 to joystickinput to switch to ANALOG MODE
                killall -q -USR1 joystickinput
                touch /tmp/fbdisplay_exit
                cat /dev/zero > /dev/fb0
                export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/a30/sdl2"
                export LD_LIBRARY_PATH="/usr/miyoo/lib"
                /mnt/SDCARD/spruce/bin/python/bin/MainUI /mnt/SDCARD/App/PyUI/main-ui/mainui.py -device MIYOO_A30 -logDir "/mnt/SDCARD/Saves/spruce" -pyUiConfig "/mnt/SDCARD/App/PyUI/py-ui-config.json" >> /dev/null 2>&1

                # remove soft link
                rm /dev/ttyS0

                ;;

            "Brick" | "SmartPro" )
                tinymix set 9 1
                tinymix set 1 0

                export LD_LIBRARY_PATH=/usr/trimui/lib:$LD_LIBRARY_PATH
                cd /usr/trimui/bin

                runifnecessary "keymon" keymon
                runifnecessary "inputd" trimui_inputd
                runifnecessary "scened" trimui_scened
                runifnecessary "trimui_btmanager" trimui_btmanager
                runifnecessary "hardwareservice" hardwareservice
             
                # the next two lines are the contents of /usr/trimui/bin/premainui.sh. I moved them
                # here for greater transparency and control (e.g. what if another CSW modified those
                # files since NAND is writeable on the TrimUI devices?)
                rm -f /tmp/trimui_inputd/input_no_dpad
                rm -f /tmp/trimui_inputd/input_dpad_to_joystick
             
                touch /tmp/fbdisplay_exit
                cat /dev/zero > /dev/fb0
                export PYSDL2_DLL_PATH="/usr/trimui/lib"
                export LD_LIBRARY_PATH="/usr/trimui/lib"
				/mnt/SDCARD/spruce/scripts/iconfresh.sh
                /mnt/SDCARD/spruce/flip/bin/MainUI /mnt/SDCARD/App/PyUI/main-ui/mainui.py -device TRIMUI_BRICK -logDir "/mnt/SDCARD/Saves/spruce" -pyUiConfig "/mnt/SDCARD/App/PyUI/py-ui-config.json" >> /dev/null 2>&1

                preload.sh

                if [ -f /tmp/trimui_inputd_restart ] ; then
                    #restart before emulator run
                    killall -9 trimui_inputd
                    sleep 0.2
                    runifnecessary "inputd" trimui_inputd
                    rm /tmp/trimui_inputd_restart 
                fi
                ;;

            "Flip" )
                export LD_LIBRARY_PATH=/usr/miyoo/lib:$LD_LIBRARY_PATH
                insmod /lib/modules/rtk_btusb.ko
                runifnecessary "btmanager" /usr/miyoo/bin/btmanager
                runifnecessary "hardwareservice" /usr/miyoo/bin/hardwareservice
                runifnecessary "miyoo_inputd" /usr/miyoo/bin/miyoo_inputd
                cd /usr/miyoo/bin/
                export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
				/mnt/SDCARD/spruce/scripts/iconfresh.sh
                /mnt/SDCARD/spruce/flip/bin/MainUI /mnt/SDCARD/App/PyUI/main-ui/mainui.py -device MIYOO_FLIP -logDir "/mnt/SDCARD/Saves/spruce" -pyUiConfig "/mnt/SDCARD/App/PyUI/py-ui-config.json" >> /dev/null 2>&1
                ;;
        esac

        # This is to block any games from launching before all necessary assets such as cores have been unpacked
        if flag_check "pre_cmd_unpacking"; then
            [ "$PLATFORM" = "SmartPro" ] && BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" || BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
            display -t "Finishing up unpacking archives.........." -i "$BG_TREE"
            flag_remove "silentUnpacker"
            while [ -f "$FLAGS_DIR/pre_cmd_unpacking.lock" ]; do
                : # null operation (no sleep needed)
            done
        fi

        flag_remove "in_menu"
    fi

    # clear the FB to get rid of residual Loading or Iconfresh screen if present
    touch /tmp/fbdisplay_exit
    cat /dev/zero > /dev/fb0

    # When you select a game or app, MainUI writes that command to a temp file and closes itself.
    # This section handles what becomes of that temp file.
    if [ -f /tmp/cmd_to_run.sh ]; then

        set_performance # lead with this to speed up launching

        kill -9 $(pgrep -f simple_mode_watchdog.sh) 2>/dev/null # Kill simple mode watchdog

        udpbcast -f /tmp/host_msg 2>/dev/null &
        touch /tmp/miyoo_inputd/enable_turbo_input 2>/dev/null # Enables turbo buttons in-game for Flip
        chmod a+x /tmp/cmd_to_run.sh
        cp /tmp/cmd_to_run.sh "$FLAGS_DIR/lastgame.lock" # set up autoresume

        /tmp/cmd_to_run.sh &>/dev/null
        
        rm /tmp/cmd_to_run.sh
        rm /tmp/host_msg 2>/dev/null
        rm /tmp/miyoo_inputd/enable_turbo_input 2>/dev/null # Disables turbo buttons in menu for Flip
        killall -9 udpbcast 2>/dev/null

        # reset CPU settings to defaults in case an emulator changes anything
        scaling_min_freq=1008000 ### default value, may be overridden in specific script
        set_smart

        /mnt/SDCARD/spruce/scripts/simple_mode_watchdog.sh & # Long live simple mode watchdog
    fi

    # set gs.lock flag if last loaded program is real game and gs.fix flag is set
    if setting_get "runGSOnGameExit" && \
       grep -q /mnt/SDCARD/Emu/*/../.emu_setup/standard_launch.sh "$FLAGS_DIR/lastgame.lock" ; then
        touch /mnt/SDCARD/spruce/flags/gs.lock
    fi

    # Set up by spruce/scripts/credits_watchdog.sh
    if [ -f /mnt/SDCARD/spruce/flags/credits.lock ]; then
        /mnt/SDCARD/App/Credits/launch.sh
        rm /mnt/SDCARD/spruce/flags/credits.lock
    fi

    if flag_check "tmp_update_repair_attempted"; then
        flag_remove "tmp_update_repair_attempted"
        log_message ".tmp_update folder repair appears to have been successful. Removing tmp_update_repair_attempted flag."
    fi

    sanitize_system_json

done
