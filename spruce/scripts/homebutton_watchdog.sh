#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** homebutton_watchdog.sh: helperFunctions imported." -v

if [ "$PLATFORM" = "A30" ]; then
    log_message "*** homebutton_watchdog.sh: PLATFORM = A30" -v
    BIN_PATH="/mnt/SDCARD/spruce/bin"
elif [ "$PLATFORM" = "Brick" ]; then
    log_message "*** homebutton_watchdog.sh: PLATFORM = Brick" -v
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
elif [ "$PLATFORM" = "SmartPro" ]; then
    log_message "*** homebutton_watchdog.sh: PLATFORM = SmartPro" -v
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
elif [ "$PLATFORM" = "Flip" ]; then
    log_message "*** homebutton_watchdog.sh: PLATFORM = Flip" -v
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
fi

SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
TEMP_PATH="/tmp"
LIST_FILE="$SETTINGS_PATH/gs_list"
TEMP_FILE="$TEMP_PATH/gs_list_temp"
RETROARCH_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"

kill_emulator() {
    # kill RA or other emulator or MainUI
    log_message "*** homebutton_watchdog.sh: Killing all Emus and MainUI!" -v

    if pgrep -x "./drastic" >/dev/null; then
        # use sendevent to send MENU + L1 combin buttons to drastic
        {
            #echo 1 28 0  # START up, to avoid screen brightness is changed by L1 key press below
            echo 1 1 1  # MENU down
            echo 1 15 1 # L1 down
            echo 1 15 0 # L1 up
            echo 1 1 0  # MENU up
            echo 0 0 0  # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
    elif pgrep "PPSSPPSDL" >/dev/null; then
        killall -q -CONT PPSSPPSDL
        # use sendevent to send SELECT + R1 combin buttons to PPSSPP
        {
            # send autosave hot key
            echo 1 314 1 # SELECT down
            echo 1 311 1 # R1 down
            echo 1 311 0 # R1 up
            echo 1 314 0 # SELECT up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event4
        # wait 1 seconds for ensuring saving is started
        sleep 1
        # kill PPSSPP with signal 15, it should exit after saving is done
        killall -15 PPSSPPSDL
    else
        killall -q -CONT pico8_dyn
        killall -q -15 ra32.miyoo retroarch ra64.trimui_$PLATFORM ra64.miyoo pico8_dyn
    fi
}

kill_current_app() {
    # Check if there's a running command
    if [ -f "/tmp/cmd_to_run.sh" ]; then
        CMD=$(cat /tmp/cmd_to_run.sh)

        # If it's an emulator (but not Ports or Media), use emulator killing logic
        if echo "$CMD" | grep -q '/mnt/SDCARD/Emu' && ! echo "$CMD" | grep -q '/mnt/SDCARD/Emu/\(PORTS\|MEDIA\)'; then
            kill_emulator
        else
            rm /tmp/cmd_to_run.sh

            # Look for any process running with "./" prefix
            for PID in /proc/[0-9]*; do
                if grep -q "^\./\|^\./" "$PID/cmdline" 2>/dev/null; then
                    KILL_PID=$(basename "$PID")
                    log_message "Killing local process with PID: $KILL_PID" -v
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
        log_message "*** homebutton_watchdog.sh: $CMD" -v

        # check command is emulator
        # exit if not emulator is in command
        if echo "$CMD" | grep -q -v '/mnt/SDCARD/Emu'; then
            return 0
        fi

        # capture screenshot
        GAME_PATH=$(echo $CMD | cut -d\" -f4)
        GAME_NAME="${GAME_PATH##*/}"
        SHORT_NAME="${GAME_NAME%.*}"
        EMU_NAME="$(echo "$GAME_PATH" | cut -d'/' -f5)"
        SCREENSHOT_NAME="/mnt/SDCARD/Saves/screenshots/${EMU_NAME}/${SHORT_NAME}.png"
        # ensure folder exists
        mkdir -p "/mnt/SDCARD/Saves/screenshots/${EMU_NAME}"
        # covert and compress framebuffer to PNG in background
        $BIN_PATH/fbgrab -a -f "/tmp/fb0" -w $DEVICE_WIDTH -h $DEVICE_HEIGHT -b 32 -l $DEVICE_WIDTH "$SCREENSHOT_NAME" 2>/dev/null &
        log_message "*** homebutton_watchdog.sh: capture screenshot" -v

        # update switcher game list
        if [ -f "$LIST_FILE" ]; then
            # if game list file exists
            # get all commands except the current game
            log_message "*** homebutton_watchdog.sh: Appending command to list file" -v
            grep -Fxv "$CMD" "$LIST_FILE" >"$TEMP_FILE"
            mv "$TEMP_FILE" "$LIST_FILE"
            # append the command for current game to the end of game list file
            echo "$CMD" >>"$LIST_FILE"
        else
            # if game list file does not exist
            # put command to new game list file
            log_message "*** homebutton_watchdog.sh: Creating new list file" -v
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
        log_message "*** homebutton_watchdog.sh: EMU_PATH = $EMU_PATH" -v
        GAME_PATH=$(echo $CMD | cut -d\" -f4)
        log_message "*** homebutton_watchdog.sh: GAME_PATH = $GAME_PATH" -v
        if [ ! -f "$EMU_PATH" ]; then
            log_message "*** homebutton_watchdog.sh: EMU_PATH does not exist!" -v
            continue
        fi
        if [ ! -f "$GAME_PATH" ]; then
            log_message "*** homebutton_watchdog.sh: GAME_PATH does not exist!" -v
            continue
        fi
        echo "$CMD" >>"$TEMP_FILE"
    done <$LIST_FILE

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
    log_message "*** homebutton_watchdog.sh: flag file created for gs" -v
}

send_virtual_key_MENUX() {
    
    if [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "SmartPro" ]; then
        {
        echo 1 316 1 # MENU down
        echo 1 308 1 # X down
        sleep 0.1
        echo 1 308 0 # X up
        echo 1 316 0 # MENU up
        echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
    fi

    if [ "$PLATFORM" = "Flip" ]; then
        {
        echo 1 314 1 # SELECT down
        echo 1 308 1 # X down
        sleep 0.1
        echo 1 308 0 # X up
        echo 1 316 0 # SELECT up
        echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
    fi
    
}

# Send L3 and R3 press event, this would toggle in-game and pause in RA
# or toggle in-game menu in PPSSPP
send_virtual_key_L3R3() {
    {
        echo 1 316 0 # MENU up
        echo 1 317 1 # L3 down
        echo 1 318 1 # R3 down
        sleep 0.1
        echo 1 318 0 # R3 up
        echo 1 317 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent /dev/input/event4
}

send_virtual_key_L3() {
    {
        echo 1 316 0 # MENU up
        echo 1 317 1 # L3 down
        sleep 0.1
        echo 1 317 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent /dev/input/event4
}

# Send R3 press event, this would toggle pause in RA
send_virtual_key_R3() {
    # Only pause RA if it is running and their hotkey is not 'escape'
    hotkey_value=$(grep '^input_enable_hotkey = ' "$RETROARCH_CFG" | cut -d '"' -f 2)
    if [ "$hotkey_value" != "escape" ]; then
        {
            echo 1 318 1 # R3 down
            sleep 0.1
            echo 1 318 0 # R3 up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event4
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
        log_message "*** homebutton_watchdog.sh: HOLD_HOME = $HOLD_HOME" -v
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
                log_message "*** homebutton_watchdog.sh: Trimui RA" -v
                  send_virtual_key_MENUX
            elif pgrep "retroarch" >/dev/null; then
                send_virtual_key_L3R3
            elif pgrep "PPSSPPSDL" >/dev/null; then
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
$BIN_PATH/getevent /dev/input/event3 -pid $$ | while read line; do
  log_message "*** homebutton_watchdog.sh: $line" -v
    home_key_down () {
        # Generate random ID for this press
        HELD_ID="$(date +%s%N)"
        # start long press handler with ID
        log_message "*** homebutton_watchdog.sh: LAUNCHING LONG PRESS HANDLER" -v
        long_press_handler "$HELD_ID" &
        PID=$!

        # pause PPSSPP, PICO8 or MainUI if it is running
        killall -q -STOP PPSSPPSDL pico8_dyn MainUI

        # copy framebuffer to memory temp file
        cp /dev/fb0 /tmp/fb0

        # pause RA after screen capture
        send_virtual_key_R3
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
                  log_message "*** homebutton_watchdog.sh: Miyoo RA32/RA64" -v
                    send_virtual_key_L3
                elif pgrep "ra64.trimui_$PLATFORM" >/dev/null || pgrep "ra64.miyoo" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: Trimui RA" -v
                    send_virtual_key_MENUX
                elif pgrep "retroarch" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: RetroArch" -v
                    send_virtual_key_L3R3
                elif pgrep "PPSSPPSDL" >/dev/null; then
                  log_message "*** homebutton_watchdog.sh: PPSSPPSDL" -v
                    send_virtual_key_L3
                    killall -q -CONT PPSSPPSDL

                # PICO8 has no in-game menu
                elif pgrep "pico8_dyn" >/dev/null; then
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
            killall -q -CONT MainUI
            # TODO: need to fix vibrate for Brick
            if [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "Flip" ]; then
              vibrate
            fi
            kill_current_app
            log_message "Exit hotkey hit"
        fi
    }

    case $line in
    # Home key down
    *"$B_MENU 1"*)
            home_key_down
        ;;
    # Home key up
    *"$B_MENU 0"*)
            home_key_up
        ;;
    # Start button down
    *"$B_START 1"*)
            start_button_down
        ;;
    # R1 in menu toggles recording
    *"$B_R1 1"*)
        if [ -f "$TEMP_PATH/gs.longpress" ] && flag_check "developer_mode" && flag_check "in_menu"; then
            record_video &
        fi
        ;;
    # R2 take screenshot
    *"$B_R2 1"*)
        if [ -f "$TEMP_PATH/gs.longpress" ] && { flag_check "developer_mode" || flag_check "designer_mode"; }; then
            take_screenshot
        fi
        ;;
    # Don't react to dpad presses
    *"$B_LEFT"* | *"$B_RIGHT"* | *"$B_UP"* | *"$B_DOWN"*) ;;
    # Any other key press while menu is held
    *"key"*)
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
                send_virtual_key_R3 # Unpause RetroArch

                log_message "*** homebutton_watchdog.sh: Additional key pressed during menu hold" -v
            fi
        fi
        ;;
    esac
done