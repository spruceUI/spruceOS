#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** homebutton_watchdog.sh: helperFunctions imported." -v

SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
TEMP_PATH="/tmp"
LIST_FILE="$SETTINGS_PATH/gs_list"
TEMP_FILE="$TEMP_PATH/gs_list_temp"
RETROARCH_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"

# Pattern for checking emulator usage
EMU_PATTERN="/(mnt/SDCARD|media/sdcard[0,1])/Emu"

kill_port(){
    CMD=$(cat /tmp/cmd_to_run.sh)
    if [[ "$CMD" == *"/Roms/PORTS/"* ]]; then
        rm -f /tmp/menubtn
        scan=true
        take_screenshot
        while $scan; do

            # Run the ps command, filter for 'box86', and exclude the grep process itself
            pid=$(ps -f | grep -E "box86|box64|mono|tee|gmloader|love.aarch64" | grep -v "grep" | awk 'NR==1 {print $1}')

            # Check if a PID was found
            if [ -n "$pid" ]; then
                log_message "Killing $pid ..." -v
                kill -9 $pid
            else
                scan=false
            fi
        done
    fi
}


# TODO bypass all of this if drastic original as killall -15 does not work on it
pause_drastic(){
    if pgrep -f "./drastic(32|64)?" >/dev/null; then
        log_message "*** homebutton_watchdog.sh: Pausing drastic!" 
        killall -q -STOP drastic drastic64 drastic32
    fi
}

resume_drastic(){
    if pgrep -f "./drastic(32|64)?" >/dev/null; then
        log_message "*** homebutton_watchdog.sh: Resuming drastic!" 
        killall -q -CONT drastic drastic64 drastic32
    fi
}

kill_drastic() {

    resume_drastic 
	log_message "*** homebutton_watchdog.sh: Killing drastic!" 
    # use sendevent to send MENU + L1 combo buttons to drastic
    {
        #echo 1 28 0  # START up, to avoid screen brightness is changed by L1 key press below
        echo $B_MENU 1  # MENU down
        echo $B_L1 1 # L1 down
        echo $B_L1 0 # L1 up
        echo $B_MENU 0  # MENU up
        echo 0 0 0  # tell sendevent to exit
    } | sendevent $EVENT_PATH_KEYBOARD &

    killall -q -15 drastic drastic64 drastic32
}

kill_ppsspp() {
	log_message "*** homebutton_watchdog.sh: Killing PPSSPP!" 

    # use sendevent to send SELECT + R1 combo buttons to PPSSPP
    {
        # send autosave hot key
        echo $B_SELECT 1 # SELECT down
        echo $B_R1 1 # R1 down
        echo $B_R1 0 # R1 up
        echo $B_SELECT 0 # SELECT up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_JOYPAD
    # wait 1 seconds for ensuring saving is started
    sleep 1
    # kill PPSSPP with signal 15, it should exit after saving is done
    killall -q -15 PPSSPPSDL
    killall -q -15 PPSSPPSDL_$PLATFORM
    killall -q -15 PPSSPPSDL_TrimUI
}

kill_ra_and_standard_emulators() { 
	log_message "*** homebutton_watchdog.sh: Killing miscelaneous emus!" 
    # Why CONT here?
    killall -q -CONT pico8_dyn pico8_64
    killall -q -15 ra32.miyoo retroarch retroarch-flip ra64.trimui_$PLATFORM ra64.miyoo pico8_dyn pico8_64 flycast yabasanshiro yabasanshiro.trimui mupen64plus
}

kill_emulator() {
    if pgrep -f "./drastic(32|64)?" >/dev/null; then
        kill_drastic
    elif pgrep -f "./PPSSPPSDL" >/dev/null; then
        kill_ppsspp
    else
        kill_ra_and_standard_emulators
    fi
}

update_gameswitcher_json() {
    CMD="$1"
    SCREENSHOT_NAME="$2"

    # -------------------------------
    # Extract system + rom path
    # -------------------------------
    game_system_name="$(printf '%s' "$CMD" | sed -n 's:.*Emu/\([^/]*\)/.*:\1:p')"
    rom_file_path="$(printf '%s' "$CMD" | sed 's:.*"\([^"]*\)" *$:\1:')"
    rom_file_path=$(readlink -f "$rom_file_path")
    # Keep consistent between devices
    rom_file_path="${rom_file_path//\/sdcard\//\/SDCARD\/}"
    gameswitcher_json="/mnt/SDCARD/Saves/gameswitcher.json"

    # Create file if missing
    [ ! -f "$gameswitcher_json" ] && echo "[]" > "$gameswitcher_json"

    tmpfile="$(mktemp)"

    # -------------------------------
    # Update JSON (remove duplicates + add new entry to top)
    # -------------------------------
    jq --arg rom_file_path "$rom_file_path" \
       --arg game_system_name "$game_system_name" '
        map(select(.rom_file_path != $rom_file_path)) |
        ([{
            rom_file_path: $rom_file_path,
            game_system_name: $game_system_name
        }] + .)
       ' "$gameswitcher_json" > "$tmpfile"

    mv "$tmpfile" "$gameswitcher_json"
}

close_ppsspp_menu() {

    if pgrep -f "PPSSPPSDL" >/dev/null; then
        log_message "*** homebutton_watchdog.sh: Closing PPSPP Menu"
        # use sendevent to send SELECT + R1 combo buttons to PPSSPP
        {
            echo $B_RIGHT 1  
            echo $B_RIGHT 0  
            echo $B_A 1  
            echo $B_A 0  
        } > /tmp/ppsspp_events.txt


        # run sendevent in a fully detached subshell
        (
            sendevent $EVENT_PATH_JOYPAD < /tmp/ppsspp_events.txt
        ) < /dev/null > /dev/null 2>&1 &

        sleep 0.5
    fi

}


take_screenshot(){
    # capture screenshot
    CMD=$(cat /tmp/cmd_to_run.sh)
    GAME_PATH=$(echo "$CMD" | grep -o '".*"' | tail -n1 | tr -d '"')
    GAME_NAME="${GAME_PATH##*/}"
    SHORT_NAME="${GAME_NAME%.*}"
    mkdir -p "/mnt/SDCARD/Saves/states/.gameswitcher"
    SCREENSHOT_NAME="/mnt/SDCARD/Saves/states/.gameswitcher/${SHORT_NAME}.state.auto.png"

    close_ppsspp_menu
    if [ "$PLATFORM" = "A30" ]; then
        /mnt/SDCARD/spruce/a30/screenshot.sh "$SCREENSHOT_NAME" 
    else
        /mnt/SDCARD/spruce/flip/screenshot.sh "$SCREENSHOT_NAME" 
    fi

    log_message "*** homebutton_watchdog.sh: 'SCREENSHOT_NAME': $SCREENSHOT_NAME" 
}

prepare_game_switcher() {
    # if in game or app now
    if [ -f /tmp/cmd_to_run.sh ]; then

        # get game path
        CMD=$(cat /tmp/cmd_to_run.sh)


        # check command is emulator
        # exit if not emulator is in command
        if echo "$CMD" | grep -q -v -E "$EMU_PATTERN"; then
            log_message "*** homebutton_watchdog.sh: Not in game, bypassing game switcher." 
            return 0
        fi

        SCREENSHOT_NAME=$(take_screenshot)

        update_gameswitcher_json "$CMD" "$SCREENSHOT_NAME"
        touch /mnt/SDCARD/App/PyUI/pyui_gs_trigger

        kill_emulator

    # if in MainUI menu
    elif pgrep "MainUI" >/dev/null; then

        log_message "*** homebutton_watchdog.sh: letting PyUI handle menu button" 
    # otherwise other program is running, exit normally
    fi

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
    } | sendevent $EVENT_PATH_JOYPAD
}

send_virtual_key_L3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        sleep 0.1
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_JOYPAD
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
        } | sendevent $EVENT_PATH_JOYPAD
    fi
}

send_menu_button_to_emu() {
    if pgrep "ra32.miyoo" >/dev/null; then
        send_virtual_key_L3
    elif pgrep "ra64.trimui_$PLATFORM" >/dev/null || pgrep "ra64.miyoo" >/dev/null; then
        echo "MENU_TOGGLE" | netcat -u -w0.1 127.0.0.1 55355
    elif pgrep -f "retroarch" >/dev/null; then
        if [ "$PLATFORM" = "A30" ]; then
            send_virtual_key_L3R3
        else
            echo "MENU_TOGGLE" | netcat -u -w0.1 127.0.0.1 55355
        fi
    elif pgrep -f "PPSSPPSDL" >/dev/null; then
        send_virtual_key_L3
    fi
    # PICO8 has no in-game menu and
    # NDS has 2 in-game menus that are activated by hotkeys with menu button short tap
}

perform_action() {
    # handle short press
    case $1 in
    "Game Switcher")
        prepare_game_switcher
        ;;
    "Emulator menu")
        send_menu_button_to_emu
        ;;
    "Exit game")
        # resume MainUI if it is running
        # and it will then read menu up event and show popup menu
        killall -q -CONT MainUI
        # or kill any emulator
        kill_emulator
        ;;
    esac
}

cancel_menu_hold() {
    # If the menu button is currently held, cancel both tap and hold
    if [ -e /tmp/menubtn ]; then
        touch /tmp/menubtn_cancelled
        if [ -n "$menu_hold_pid" ]; then
            kill "$menu_hold_pid" 2>/dev/null
            wait "$menu_hold_pid" 2>/dev/null
            menu_hold_pid=""
        fi
    fi
}

# listen to log file and handle key press events
# the keypress logs are generated by keymon
getevent -pid $$ $EVENT_PATH_KEYBOARD | while read line; do
    log_message "*** homebutton_watchdog.sh: $line" -v

    home_key_down () {

        if [ ! -e /tmp/menubtn ]; then
            pause_drastic
            menu_btn_press_time=$(date +%s)
            log_message "Menu button pressed at $menu_btn_press_time" 
            touch /tmp/menubtn

            # Launch background timer that waits required seconds, then triggers the action
            (
                menu_hold_time=$(get_config_value '.menuOptions."Game Switcher Settings".menuHoldTime.selected' 2)
                sleep "$menu_hold_time"
                # Check if the menubtn file still exists (i.e. button still held) AND NOT cancelled (i.e. no other button pressed)
                if [ -e /tmp/menubtn ] && [ ! -e /tmp/menubtn_cancelled ]; then
                    rm -f /tmp/menubtn
                    rm -f /tmp/menubtn_cancelled
                    do_vibrate="$(get_config_value '.menuOptions."Game Switcher Settings".menuShouldVibrate.selected' "True")"
                    # Only vibrate if enabled
                    if [ "$do_vibrate" = "True" ]; then
                        vibrate 
                    fi
                    HOLD_HOME="$(get_config_value '.menuOptions."Emulator Settings".holdHomeAction.selected' "Game Switcher")"
                    log_message "*** homebutton_watchdog.sh: Performing hold-home action: $HOLD_HOME"
                    perform_action "$HOLD_HOME"

                fi
            ) &
            menu_hold_pid=$!

            kill_port
        fi
    }

    home_key_up () {
        log_message "Menu button released at $(date +%s)"  
        if [ -e /tmp/menubtn ]; then
            rm -f /tmp/menubtn

            was_cancelled=false
            if [ -e /tmp/menubtn_cancelled ]; then
                was_cancelled=true
                rm -f /tmp/menubtn_cancelled
            fi

            # Kill background hold timer if still running
            if [ -n "$menu_hold_pid" ]; then
                kill "$menu_hold_pid" 2>/dev/null
                wait "$menu_hold_pid" 2>/dev/null
                menu_hold_pid=""
            fi

            if [ "$was_cancelled" = false ]; then
                TAP_HOME="$(get_config_value '.menuOptions."Emulator Settings".tapHomeAction.selected' "Emulator menu")"
                log_message "*** homebutton_watchdog.sh: Performing tap-home action: $TAP_HOME"
                perform_action "$TAP_HOME"
            fi

            resume_drastic
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

        *"key $B_START 1"*  | \
        *"key $B_SELECT 1"* | \
        *"key $B_R1"*      | \
        *"key $B_R2"*      | \
        *"key $B_L1"*      | \
        *"key $B_L2"*      | \
        *"key $B_A 1"*     | \
        *"key $B_B 1"*     | \
        *"key $B_X 1"*     | \
        *"key $B_Y 1"*     | \
        *"key $B_VOLUP 1"* | \
        *"key $B_VOLDOWN 1"* | \
        *"key $B_LEFT"*    | \
        *"key $B_RIGHT"*   | \
        *"key $B_UP"*      | \
        *"key $B_DOWN"* )
            cancel_menu_hold
            resume_drastic
            ;;

    esac
done
