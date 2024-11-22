#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** gameswitcher_watchdog.sh: helperFunctions imported." -v

INFO_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"
DEFAULT_IMG="/mnt/SDCARD/Themes/SPRUCE/icons/ports.png"

BIN_PATH="/mnt/SDCARD/spruce/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
TEMP_PATH="/tmp"
LIST_FILE="$SETTINGS_PATH/gs_list"
MAX_COUNT_FILE="$SETTINGS_PATH/gs_max"
TEMP_FILE="$TEMP_PATH/gs_list_temp"
CFG_FILE="/mnt/SDCARD/spruce/settings/spruce.cfg"

kill_emulator() {
    # kill RA or other emulator or MainUI
    log_message "*** gameswitcher_watchdog.sh: Killing all Emus and MainUI!" -v

    if pgrep -x "./drastic" > /dev/null ; then
        # use sendevent to send MENU + L1 combin buttons to drastic  
        {
            #echo 1 28 0  # START up, to avoid screen brightness is changed by L1 key press below
            echo 1 1 1   # MENU down
            echo 1 15 1  # L1 down
            echo 1 15 0  # L1 up
            echo 1 1 0   # MENU up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
    elif pgrep "PPSSPPSDL" > /dev/null ; then
        killall -q -CONT PPSSPPSDL
        # use sendevent to send SELECT + L2 combin buttons to PPSSPP  
        {
            # send autosave hot key
            echo 1 314 1  # SELECT down
            echo 3 2 255  # L2 down
            echo 3 2 0    # L2 up
            echo 1 314 0  # SELECT up
            echo 0 0 0    # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event4
        # wait 1 seconds for ensuring saving is started
        sleep 1
        # kill PPSSPP with signal 15, it should exit after saving is done
        killall -15 PPSSPPSDL
    else
        killall -q -CONT pico8_dyn
        killall -q -15 ra32.miyoo retroarch pico8_dyn
    fi
}

prepare_game_switcher() {
    # if in game or app now
    if [ -f /tmp/cmd_to_run.sh ] ; then

        # get game path
        CMD=$(cat /tmp/cmd_to_run.sh)
        log_message "*** gameswitcher_watchdog.sh: $CMD" -v

        # check command is emulator
        # exit if not emulator is in command
        if echo "$CMD" | grep -q -v '/mnt/SDCARD/Emu' ; then
            return 0
        fi

        # capture screenshot
        GAME_PATH=$(echo $CMD | cut -d\" -f4)
        GAME_NAME="${GAME_PATH##*/}"
        SHORT_NAME="${GAME_NAME%.*}"
        EMU_NAME="$(echo "$GAME_PATH" | cut -d'/' -f5)"
        # ensure folder exists
        mkdir -p "/mnt/SDCARD/Saves/screenshots/${EMU_NAME}"
        # ensure framebuffer information is set correctly
        $BIN_PATH/fbfixcolor
        # capture screenshot
        $BIN_PATH/fbgrab -a "/mnt/SDCARD/Saves/screenshots/${EMU_NAME}/${SHORT_NAME}.png"
        log_message "*** gameswitcher_watchdog.sh: capture screenshot" -v

        # update switcher game list
        if [ -f "$LIST_FILE" ] ; then
            # if game list file exists
            # get all commands except the current game
            log_message "*** gameswitcher_watchdog.sh: Appending command to list file" -v
            grep -Fxv "$CMD" "$LIST_FILE" > "$TEMP_FILE"
            mv "$TEMP_FILE" "$LIST_FILE"
            # append the command for current game to the end of game list file 
            echo "$CMD" >> "$LIST_FILE"
        else
            # if game list file does not exist
            # put command to new game list file
            log_message "*** gameswitcher_watchdog.sh: Creating new list file" -v
            echo "$CMD" > "$LIST_FILE"
        fi

    # if in MainUI menu
    elif pgrep -x "./MainUI" > /dev/null ; then

        # exit if list file does not exist
        if [ ! -f "$LIST_FILE" ] ; then
            return 0
        fi

    # otherwise other program is running, exit normally
    else
        return 0
    fi

    # makesure all emulators and games in list exist
    # remove all non existing games from list file
    rm -f "$TEMP_FILE"
    while read -r CMD; do
        EMU_PATH=$(echo $CMD | cut -d\" -f2)
        log_message "*** gameswitcher_watchdog.sh: EMU_PATH = $EMU_PATH" -v
        GAME_PATH=$(echo $CMD | cut -d\" -f4)
        log_message "*** gameswitcher_watchdog.sh: GAME_PATH = $GAME_PATH" -v
        if [ ! -f "$EMU_PATH" ] ; then 
            log_message "*** gameswitcher_watchdog.sh: EMU_PATH does not exist!" -v
            continue
        fi
        if [ ! -f "$GAME_PATH" ] ; then
            log_message "*** gameswitcher_watchdog.sh: GAME_PATH does not exist!" -v
            continue
        fi
        echo "$CMD" >> "$TEMP_FILE"
    done <$LIST_FILE

    # trim the game list to only recent 5/10/20 games
    setting_get "maxGamesInGS"
    COUNT=$?
    if [ $COUNT -eq 0 ] ; then
        COUNT=10
    fi
    tail -$COUNT "$TEMP_FILE" > "$LIST_FILE"

    # kill RA or other emulator or MainUI
    kill_emulator
    killall -q -9 MainUI

    # set flag file for principal.sh to load game switcher later
    flag_add "gs"
    log_message "*** gameswitcher_watchdog.sh: flag file created for gs" -v
}

# Send L3 and R3 press event, this would toggle in-game and pause in RA
# or toggle in-game menu in PPSSPP
send_virtual_key_L3R3() {
    {
        echo 1 316 0   # MENU up
        echo 1 317 1   # L3 down
        echo 1 318 1   # R3 down
        sleep 0.1
        echo 1 318 0   # R3 up
        echo 1 317 0   # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent /dev/input/event4    
}

send_virtual_key_L3() {
    {
        echo 1 316 0   # MENU up
        echo 1 317 1   # L3 down
        sleep 0.1
        echo 1 317 0   # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent /dev/input/event4    
}

# Send R3 press event, this would toggle pause in RA
send_virtual_key_R3() {
    {
        echo 1 318 1   # R3 down
        sleep 0.1
        echo 1 318 0   # R3 up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent /dev/input/event4    
}

long_press_handler() {
    # setup flag for long pressed event
    touch "$TEMP_PATH/gs.longpress"
    sleep 1.6
    rm "$TEMP_PATH/gs.longpress"

    # if IS long press
    vibrate
    
    # get setting
    HOLD_HOME=$(setting_get "hold_home")
    log_message "*** gameswitcher_watchdog.sh: HOLD_HOME = $HOLD_HOME" -v
    [ -z "$HOLD_HOME" ] && HOLD_HOME="Game Switcher"
    
    case $HOLD_HOME in
        "Game Switcher")
            prepare_game_switcher
        ;;
        "In-game menu")
            if pgrep "ra32.miyoo" > /dev/null ; then
                send_virtual_key_L3

            elif pgrep "retroarch" > /dev/null ; then
                send_virtual_key_L3R3

            elif pgrep "PPSSPPSDL" > /dev/null ; then
                send_virtual_key_L3
                killall -q -CONT PPSSPPSDL

            # PICO8 has no in-game menu and 
            # NDS has 2 in-game menus that are activated by hotkeys with menu button short tap  
            else
                # resume MainUI if it is running
                # and it will then read menu up event and show popup menu
                killall -q -CONT  MainUI
                # or kill NDS or PICO8
                kill_emulator
            fi
        ;;
        "Exit game")
            # resume MainUI if it is running
            # and it will then read menu up event and show popup menu
            killall -q -CONT  MainUI
            # or kill any emulator
            kill_emulator
        ;;
    esac    
}

# listen to log file and handle key press events
# the keypress logs are generated by keymon
$BIN_PATH/getevent /dev/input/event3 -pid $$ | while read line; do
    case $line in
        # MENU key down
        *"key 1 1 1"*)
            # start long press handler
            log_message "*** gameswitcher_watchdog.sh: LAUNCHING LONG PRESS HANDLER" -v
            long_press_handler &
            PID=$!

            # pause RA, PPSSPP, PICO8 or MainUI if it is running
            send_virtual_key_R3
            killall -q -STOP PPSSPPSDL pico8_dyn MainUI
        ;;
        # MENU key up
        *"key 1 1 0"*)
            # if NOT long press
            if [ -f "$TEMP_PATH/gs.longpress" ] ; then
                rm "$TEMP_PATH/gs.longpress"
                kill $PID
                log_message "*** gameswitcher_watchdog.sh: LONG PRESS HANDLER ABORTED" -v

                # skip mainUI and NDS, they need short press for their hotkeys
                if pgrep "drastic" > /dev/null ; then
                    continue
                fi

                # get setting
                TAP_HOME=$(setting_get "tap_home")
                [ -z "$TAP_HOME" ] && TAP_HOME="In-game menu"

                # handle short press
                case $TAP_HOME in
                    "Game Switcher")
                        prepare_game_switcher
                    ;;
                    "In-game menu")
                        if pgrep "ra32.miyoo" > /dev/null ; then
                            send_virtual_key_L3

                        elif pgrep "retroarch" > /dev/null ; then
                            send_virtual_key_L3R3

                        elif pgrep "PPSSPPSDL" > /dev/null ; then
                            send_virtual_key_L3
                            killall -q -CONT PPSSPPSDL

                        # PICO8 has no in-game menu
                        elif pgrep "pico8_dyn" > /dev/null ; then
                            kill_emulator

                        # resume MainUI and it will then read menu up event and show popup menu
                        elif pgrep "MainUI" > /dev/null ; then
                            killall -q -CONT  MainUI
                        fi
                    ;;
                    "Exit game")
                        # resume MainUI if it is running
                        # and it will then read menu up event and show popup menu
                        killall -q -CONT  MainUI
                        # or kill any emulator
                        kill_emulator
                    ;;
                esac
            fi
        ;;
    esac
done 
