#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** homebutton_watchdog.sh: helperFunctions imported." -v

SD_FOLDER_PATH="/mnt/SDCARD"
BIN_PATH="/mnt/SDCARD/spruce/bin64"
if [ "$PLATFORM" = "A30" ]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin"
    
elif [ "$PLATFORM" = "Flip" ]; then
    SD_FOLDER_PATH="/media/sdcard0"
fi
log_message "*** homebutton_watchdog.sh: PLATFORM = $PLATFORM" -v

SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
TEMP_PATH="/tmp"
LIST_FILE="$SETTINGS_PATH/gs_list"
TEMP_FILE="$TEMP_PATH/gs_list_temp"
RETROARCH_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"

kill_port(){
	scan=true
    while $scan; do

        # Run the ps command, filter for 'box86', and exclude the grep process itself
        pid=$(ps -f | grep -E "box86|box64|mono|tee|gmloader" | grep -v "grep" | awk 'NR==1 {print $1}')

        # Check if a PID was found
        if [ -n "$pid" ]; then
            log_message "Killing $pid ..." -v
            kill -9 $pid
        else
            scan=false
        fi
    done
}

kill_emulator() {

    if pgrep -f "./drastic" >/dev/null; then
	    log_message "*** homebutton_watchdog.sh: Killing drastic!" 

        # use sendevent to send MENU + L1 combo buttons to drastic
        {
            #echo 1 28 0  # START up, to avoid screen brightness is changed by L1 key press below
            echo $B_MENU 1  # MENU down
            echo $B_L1 1 # L1 down
            echo $B_L1 0 # L1 up
            echo $B_MENU 0  # MENU up
            echo 0 0 0  # tell sendevent to exit
        } | $BIN_PATH/sendevent $EVENT_PATH_KEYBOARD
    elif pgrep -f "./PPSSPPSDL" >/dev/null; then
	    log_message "*** homebutton_watchdog.sh: Killing PPSSPPSDL!" 
        killall -q -CONT PPSSPPSDL
        killall -q -CONT PPSSPPSDL_$PLATFORM
        # use sendevent to send SELECT + R1 combo buttons to PPSSPP
        {
            # send autosave hot key
            echo $B_SELECT 1 # SELECT down
            echo $B_R1 1 # R1 down
            echo $B_R1 0 # R1 up
            echo $B_SELECT 0 # SELECT up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent $EVENT_PATH_JOYPAD
        # wait 1 seconds for ensuring saving is started
        sleep 1
        # kill PPSSPP with signal 15, it should exit after saving is done
        killall -q -15 PPSSPPSDL
        killall -q -15 PPSSPPSDL_$PLATFORM

    else
	    log_message "*** homebutton_watchdog.sh: Killing all Emus and MainUI!" 
        pid=$(ps -f | grep -E "MainUI.py" | grep -v "grep" | awk 'NR==1 {print $1}')
        if [ -n "$pid" ]; then
            log_message "Killing MainUI.py with PID: $pid"
            kill -9 $pid
        fi

        killall -q -CONT pico8_dyn pico8_64
        killall -q -15 ra32.miyoo retroarch retroarch-flip ra64.trimui_$PLATFORM ra64.miyoo pico8_dyn pico8_64 flycast yabasanshiro yabasanshiro.trimui mupen64plus
    fi
}

kill_current_app() {
    # Check if there's a running command
    if [ -f "/tmp/cmd_to_run.sh" ]; then
        CMD=$(cat /tmp/cmd_to_run.sh)

        # If it's an emulator (but not Ports or Media), use emulator killing logic
        if echo "$CMD" | grep -q "$SD_FOLDER_PATH/Emu" && ! echo "$CMD" | grep -q "$SD_FOLDER_PATH/Emu/\(PORTS\|MEDIA\)"; then
            kill_emulator
        else
            rm /tmp/cmd_to_run.sh

            # Look for any process running with "./" prefix
            for PID in /proc/[0-9]*; do
                if grep -q "^\./\|^\./" "$PID/cmdline" 2>/dev/null; then
                    KILL_PID=$(basename "$PID")
                    log_message "Killing local process with PID: $KILL_PID"
                    kill -9 "$KILL_PID" 2>/dev/null
                fi
            done
        fi
    fi
}

prepare_game_switcher() {
    # if in game or app now
    if [ -f /tmp/cmd_to_run.sh ]; then

        # get game path
        CMD=$(cat /tmp/cmd_to_run.sh)
        log_message "*** homebutton_watchdog.sh: 'CMD': $CMD"

        # check command is emulator
        # exit if not emulator is in command
        if echo "$CMD" | grep -q -v "$SD_FOLDER_PATH/Emu"; then
            return 0
        fi

        # capture screenshot
        GAME_PATH=$(echo $CMD | cut -d\" -f4)
        [ "$PLATFORM" = "Flip" ] && GAME_PATH=$(echo $CMD | cut -d\" -f6)
        log_message "*** homebutton_watchdog.sh: 'GAME_PATH': $GAME_PATH" -v
        GAME_NAME="${GAME_PATH##*/}"
        log_message "*** homebutton_watchdog.sh: 'GAME_NAME': $GAME_NAME" -v
        SHORT_NAME="${GAME_NAME%.*}"
        log_message "*** homebutton_watchdog.sh: 'SHORT_NAME': $SHORT_NAME" -v
        EMU_NAME="$(echo "$GAME_PATH" | cut -d'/' -f5)"
        log_message "*** homebutton_watchdog.sh: 'EMU_NAME': $EMU_NAME" -v
        SCREENSHOT_NAME="$SD_FOLDER_PATH/Saves/screenshots/${EMU_NAME}/${SHORT_NAME}.png"
        log_message "*** homebutton_watchdog.sh: 'SCREENSHOT_NAME': $SCREENSHOT_NAME" 
        # ensure folder exists
        mkdir -p "$SD_FOLDER_PATH/Saves/screenshots/${EMU_NAME}"
        # covert and compress framebuffer to PNG in background
        WIDTH="$DISPLAY_WIDTH"
        HEIGHT="$DISPLAY_HEIGHT"
        if [ "$PLATFORM" = "A30" ]; then # A30 is rotated 270 degrees, swap width and height
            WIDTH=$DISPLAY_HEIGHT
            HEIGHT=$DISPLAY_WIDTH
        fi

        if [ "$PLATFORM" = "A30" ]; then
            $BIN_PATH/fbgrab -a -f "/tmp/fb0" -w "$WIDTH" -h "$HEIGHT" -b 32 -l "$WIDTH" "$SCREENSHOT_NAME" 2>/dev/null &
        else
            $SD_FOLDER_PATH/spruce/flip/screenshot.sh "$SCREENSHOT_NAME" &
        fi
       
        log_message "*** homebutton_watchdog.sh: capture screenshot" -v

        # update switcher game list
        if [ -f "$LIST_FILE" ]; then
            # if game list file exists
            # get all commands except the current game
            log_message "*** homebutton_watchdog.sh: Appending command to list file" 
            grep -Fxv "$CMD" "$LIST_FILE" >"$TEMP_FILE"
            mv "$TEMP_FILE" "$LIST_FILE"
            # append the command for current game to the end of game list file
            echo "$CMD" >>"$LIST_FILE"
        else
            # if game list file does not exist
            # put command to new game list file
            log_message "*** homebutton_watchdog.sh: Creating new list file" 
            echo "$CMD" >"$LIST_FILE"
        fi

    # if in MainUI menu
    elif pgrep "MainUI" >/dev/null; then

        # exit if list file does not exist
        if [ ! -f "$LIST_FILE" ]; then
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
        log_message "*** homebutton_watchdog.sh: EMU_PATH = $EMU_PATH" 
        GAME_PATH=$(echo $CMD | cut -d\" -f4)
        [ "$PLATFORM" = "Flip" ] && GAME_PATH=$(echo $CMD | cut -d\" -f6)
        log_message "*** homebutton_watchdog.sh: GAME_PATH = $GAME_PATH" 
        if [ ! -f "$EMU_PATH" ]; then
            log_message "*** homebutton_watchdog.sh: EMU_PATH does not exist!" 
            continue
        fi
        if [ ! -f "$GAME_PATH" ]; then
            log_message "*** homebutton_watchdog.sh: GAME_PATH does not exist!" 
            continue
        fi
        echo "$CMD" >>"$TEMP_FILE"
    done <$LIST_FILE

    # TODO: i don't think this works anymore, TEMP_FILE is long gone
    # trim the game list to only recent 5/10/20 games
    COUNT=$(setting_get "maxGamesInGS")
    if [ -z "$COUNT" ]; then
        COUNT=10
    fi
    tail -$COUNT "$TEMP_FILE" >"$LIST_FILE"

    # kill RA or other emulator or MainUI
    kill_emulator
    killall -q -9 MainUI

    # set flag file for principal.sh to load game switcher later
    flag_add "gs"
    log_message "*** homebutton_watchdog.sh: flag file created for gs" 
}

# Send L3 and R3 press event, this would toggle in-game and pause in RA
# or toggle in-game menu in PPSSPP
send_virtual_key_L3R3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        echo $B_R3 1 # R3 down
        sleep 0.1
        echo $B_R3 0 # R3 up
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent $EVENT_PATH_JOYPAD
}

send_virtual_key_L3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        sleep 0.1
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent $EVENT_PATH_JOYPAD
}

# Send R3 press event, this would toggle pause in RA
send_virtual_key_R3() {
    # Only pause RA if it is running and their hotkey is not 'escape'
    hotkey_value=$(grep '^input_enable_hotkey = ' "$RETROARCH_CFG" | cut -d '"' -f 2)
    if [ "$hotkey_value" != "escape" ]; then
        {
            echo $B_R3 1 # R3 down
            sleep 0.1
            echo $B_R3 0 # R3 up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent $EVENT_PATH_JOYPAD
    fi
}

long_press_handler() {
    HELD_ID="$1"
    # setup flag for long pressed event
    touch "$TEMP_PATH/gs.longpress"
    touch "$TEMP_PATH/homeheld.$HELD_ID"
    sleep 1.5

    # Only proceed if menu was the only key pressed with our specific ID
    if [ -f "$TEMP_PATH/homeheld.$HELD_ID" ]; then
        touch "$TEMP_PATH/longpress_activated"
        vibrate

        # get setting
        HOLD_HOME=$(setting_get "hold_home")
        log_message "*** homebutton_watchdog.sh: HOLD_HOME = $HOLD_HOME" 
        [ -z "$HOLD_HOME" ] && HOLD_HOME="Game Switcher"

        if flag_check "simple_mode" && flag_check "in_menu"; then
            HOLD_HOME="Game Switcher"
        fi

        case $HOLD_HOME in
        "Game Switcher")
            prepare_game_switcher
            ;;
        "In-game menu")
            if pgrep "ra32.miyoo" >/dev/null; then
                send_virtual_key_L3
            elif pgrep "ra64.trimui_$PLATFORM" >/dev/null || pgrep "ra64.miyoo" >/dev/null; then
                echo "MENU_TOGGLE" | $BIN_PATH/netcat -u -w0.1 127.0.0.1 55355
            elif pgrep -f "retroarch" >/dev/null; then
                if [ "$PLATFORM" = "A30" ]; then
                    send_virtual_key_L3R3
                else
                    echo "MENU_TOGGLE" | $BIN_PATH/netcat -u -w0.1
                fi
            elif pgrep -f "PPSSPPSDL" >/dev/null; then
                send_virtual_key_L3
                killall -q -CONT PPSSPPSDL

            # PICO8 has no in-game menu and
            # NDS has 2 in-game menus that are activated by hotkeys with menu button short tap
            else
                # resume MainUI if it is running
                # and it will then read menu up event and show popup menu
                killall -q -CONT MainUI
                # or kill NDS or PICO8
                kill_emulator
            fi
            ;;
        "Exit game")
            # resume MainUI if it is running
            # and it will then read menu up event and show popup menu
            killall -q -CONT MainUI
            # or kill any emulator
            kill_emulator
            ;;
        esac
    fi

    rm -f "$TEMP_PATH/gs.longpress"
    rm -f "$TEMP_PATH/homeheld.$HELD_ID"
    rm -f "$TEMP_PATH/longpress_activated"
}

# listen to log file and handle key press events
# the keypress logs are generated by keymon
$BIN_PATH/getevent -pid $$ $EVENT_PATH_KEYBOARD | while read line; do
  log_message "*** homebutton_watchdog.sh: $line" -v
    home_key_down () {
        # Generate random ID for this press
        HELD_ID="$(date +%s%N)"
        # start long press handler with ID
        log_message "*** homebutton_watchdog.sh: LAUNCHING LONG PRESS HANDLER" -v
        long_press_handler "$HELD_ID" &
        PID=$!

        # pause PPSSPP, PICO8 or MainUI if it is running
        killall -q -STOP PPSSPPSDL PPSSPPSDL_$PLATFORM pico8_dyn pico8_64 MainUI

        # copy framebuffer to memory temp file
        cp /dev/fb0 /tmp/fb0

        # pause RA after screen capture
        if [ "$PLATFORM" = "A30" ]; then
          send_virtual_key_R3
        fi

        # fallback to stop ports
        kill_port
    }

    home_key_up () {
        # Clean up ALL homeheld flags
        rm -f "$TEMP_PATH"/homeheld.*
        
        # if NOT long press
        if [ -f "$TEMP_PATH/gs.longpress" ]; then
            # Only kill the long press handler if vibrate hasn't happened yet
            if [ ! -f "$TEMP_PATH/longpress_activated" ]; then
                kill $PID
                rm -f "$TEMP_PATH/gs.longpress"
                log_message "*** homebutton_watchdog.sh: LONG PRESS HANDLER ABORTED" -v
            else
                rm -f "$TEMP_PATH/longpress_activated"
            fi

            # skip mainUI and NDS, they need short press for their hotkeys
            if pgrep "drastic" >/dev/null; then
                continue
            fi

            # get setting
            TAP_HOME=$(setting_get "tap_home")
            [ -z "$TAP_HOME" ] && TAP_HOME="In-game menu"

            if flag_check "simple_mode" && flag_check "in_menu"; then
                TAP_HOME="Game Switcher"
            fi

            # handle short press
            case $TAP_HOME in
            "Game Switcher")
              log_message "*** homebutton_watchdog.sh: Game Switcher" -v
                prepare_game_switcher
                ;;
            "In-game menu")
              log_message "*** homebutton_watchdog.sh: In-game menu" -v
                if pgrep "ra32.miyoo" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: Miyoo RA32" -v
                    send_virtual_key_L3
                elif pgrep "ra64.trimui_$PLATFORM" >/dev/null || pgrep "ra64.miyoo" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: $PLATFORM RA" -v
                  echo "MENU_TOGGLE" | $BIN_PATH/netcat -u -w0.1 127.0.0.1 55355
                elif pgrep -f "retroarch" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: RetroArch" -v
                  if [ "$PLATFORM" = "A30" ]; then
                    send_virtual_key_L3R3
                  else
                    echo "MENU_TOGGLE" | $BIN_PATH/netcat -u -w0.1 127.0.0.1 55355
                  fi 
                elif pgrep -f "PPSSPPSDL" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: PPSSPPSDL" -v
                    send_virtual_key_L3
                    killall -q -CONT PPSSPPSDL
                    killall -q -CONT PPSSPPSDL_$PLATFORM

                # PICO8 has no in-game menu
                elif pgrep -f "pico8" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: PICO8" -v
                    kill_emulator

                # resume MainUI and it will then read menu up event and show popup menu
                elif pgrep "MainUI" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: MainUI" -v
                    killall -q -CONT MainUI
                fi
                ;;
            "Exit game")
              log_message "*** homebutton_watchdog.sh: Exit game" -v
                # resume MainUI if it is running
                # and it will then read menu up event and show popup menu
                killall -q -CONT MainUI
                # or kill any emulator
                kill_emulator
                ;;
            esac
        fi
    }

    start_button_down () {
        log_message "*** Start button case matched: $line" -v
        if [ -f "$TEMP_PATH/gs.longpress" ] && ! flag_check "in_menu"; then
            log_message "Exit hotkey hit"
            killall -q -CONT MainUI
            # TODO: need to fix vibrate for Brick
            if [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "Flip" ]; then
              vibrate
            fi
            kill_current_app
        fi
    }

    case $line in
    # Home key down
    *"key $B_MENU 1"*)
            home_key_down
        ;;
    # Home key up
    *"key $B_MENU 0"*)
            home_key_up
        ;;
    # Start button down
    *"key $B_START 1"*)
            start_button_down
        ;;
    # R1 in menu toggles recording
    *"key $B_R1 1"*)
        if [ -f "$TEMP_PATH/gs.longpress" ] && flag_check "developer_mode" && flag_check "in_menu"; then
            record_video &
        fi
        ;;
    # R2 take screenshot
    *"key $B_R2 1"*)
        if [ -f "$TEMP_PATH/gs.longpress" ] && { flag_check "developer_mode" || flag_check "designer_mode"; }; then
            take_screenshot
        fi
        ;;
    # Don't react to dpad presses or analog sticks
    *"key $B_LEFT"* | *"key $B_RIGHT"* | *"key $B_UP"* | *"key $B_DOWN"*| \
    *"key $STICK_LEFT"*| *"key $STICK_RIGHT"*| *"key $STICK_UP"*| *"key $STICK_DOWN"*| \
    *"key $STICK_LEFT_2"*| *"key $STICK_RIGHT_2"*| *"key $STICK_UP_2"*| *"key $STICK_DOWN_2"*) ;;
    # Any other key press while menu is held
    *"key"*"0")
        log_message "*** Catch-all key case matched: $line" -v
        if [ -f "$TEMP_PATH/gs.longpress" ]; then
            # Only remove homeheld flag if NOT in simple_mode and in_menu
            if ! { flag_check "simple_mode" && flag_check "in_menu"; }; then
                # Clear all long press related flags
                rm -f "$TEMP_PATH/gs.longpress"
                rm -f "$TEMP_PATH/homeheld.$HELD_ID"
                rm -f "$TEMP_PATH/longpress_activated"

                # Resume paused processes
                killall -q -CONT PPSSPPSDL pico8_dyn MainUI
                if [ "$PLATFORM" = "A30" ]; then
                    send_virtual_key_R3
                fi

                log_message "*** homebutton_watchdog.sh: Additional key pressed during menu hold" -v
            fi
        fi
        ;;
    esac
done
