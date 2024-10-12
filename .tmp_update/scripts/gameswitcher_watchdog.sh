#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** gameswitcher_watchdog.sh: helperFunctions imported." -v

INFO_DIR="/mnt/SDCARD/RetroArch/.retroarch/cores"
DEFAULT_IMG="/mnt/SDCARD/Themes/SPRUCE/icons/ports.png"

BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
LIST_FILE="$SETTINGS_PATH/gs_list"
TEMP_FILE="$FLAG_PATH/gs_list_temp"

long_press_handler() {
    # if in game or app now
    if [ -f /tmp/cmd_to_run.sh ] ; then

        # setup flag for long pressed event
        flag_add "gs.longpress"
        sleep 2
        flag_remove "gs.longpress"
        
        # get game path
        CMD=$(cat /tmp/cmd_to_run.sh)
        log_message "*** gameswitcher_watchdog.sh: $CMD" -v

        # check command is emulator
        # exit if not emulator is in command
        if echo "$CMD" | grep -q -v '/mnt/SDCARD/Emu' ; then
            return 0
        fi

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

        # setup flag for long pressed event
        flag_add "gs.longpress"
        sleep 2
        flag_remove "gs.longpress"
        
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
    mv "$TEMP_FILE" "$LIST_FILE"

    # trim the game list to only recent 10 games
    tail -10 "$LIST_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$LIST_FILE"

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
        # use sendevent to send SELECT + L2 combin buttons to PPSSPP  
        {
            # close in-game menu
            echo 1 316 0  # MENU up
            echo 1 316 1  # MENU down
            echo 1 316 0  # MENU up
            echo 0 0 0    # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event4
        sleep 0.5
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
    elif pgrep "ra32.miyoo" > /dev/null ; then
        # use sendevent to send A button to ra32.miyoo for closing the in-game menu  
        {
            echo 1 1 0   # MENU up
            echo 1 57 1  # A down
            echo 1 57 0  # A up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
        killall -q -15 ra32.miyoo
    else
        killall -q -15 retroarch || \
        killall -q -9 MainUI
    fi
    
    # set flag file for principal.sh to load game switcher later
    flag_add "gs"
    log_message "*** gameswitcher_watchdog.sh: flag file created for gs" -v
}

# listen to log file and handle key press events
# the keypress logs are generated by keymon
$BIN_PATH/getevent /dev/input/event3 | while read line; do
    case $line in
        *"key 1 1 1"*) # START key down
            # start long press handler
            log_message "*** gameswitcher_watchdog.sh: LAUNCHING LONG PRESS HANDLER" -v
            long_press_handler &
            PID=$!
        ;;
        *"key 1 1 0"*) # START key up
            # kill the long press handler if 
            # menu button is released within time limit
            # and is in game now
            if flag_check "gs.longpress" && [ -f /tmp/cmd_to_run.sh ] ; then
                flag_remove "gs.longpress"
                kill $PID
                log_message "*** gameswitcher_watchdog.sh: LONG PRESS HANDLER ABORTED" -v
            fi
        ;;
    esac
done 
