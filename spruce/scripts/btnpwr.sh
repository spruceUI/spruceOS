#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# Kill keymon
killall -9 keymon
vibrate


BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
LIST_FILE="$SETTINGS_PATH/gs_list"
TEMP_FILE="$FLAG_PATH/gs_list_temp"
WAS_IN_EMULATOR=1

# Not entirely sure this is necessary
update_game_list() {
    if [ -f /tmp/cmd_to_run.sh ]; then
        CMD=$(cat /tmp/cmd_to_run.sh)
        if echo "$CMD" | grep -q '/mnt/SDCARD/Emu'; then
            if [ -f "$LIST_FILE" ]; then
                grep -Fxv "$CMD" "$LIST_FILE" > "$TEMP_FILE"
                mv "$TEMP_FILE" "$LIST_FILE"
                echo "$CMD" >> "$LIST_FILE"
            else
                echo "$CMD" > "$LIST_FILE"
            fi
            
            # Trim list to recent 10 games
            tail -10 "$LIST_FILE" > "$TEMP_FILE"
            mv "$TEMP_FILE" "$LIST_FILE"
        fi
    fi
}

kill_current_process() {
    pid=$(ps | grep cmd_to_run | grep -v grep | sed 's/[ ]\+/ /g' | cut -d' ' -f2)
    ppid=$pid
    while [ "" != "$pid" ]; do
        ppid=$pid
        pid=$(pgrep -P $ppid)
    done

    if [ "" != "$ppid" ]; then
        kill -9 $ppid
    fi
}

handle_emulator_exit() {
    if pgrep -x "./drastic" > /dev/null ; then
        {
            echo 1 1 1   # MENU down
            echo 1 15 1  # L1 down
            echo 1 15 0  # L1 up
            echo 1 1 0   # MENU up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
        WAS_IN_EMULATOR=0
    elif pgrep "PPSSPPSDL" > /dev/null ; then
        {
            echo 1 316 0  # MENU up
            echo 1 316 1  # MENU down
            echo 1 316 0  # MENU up
            echo 0 0 0    # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event4
        sleep 0.5
        {
            echo 1 314 1  # SELECT down
            echo 3 2 255  # L2 down
            echo 3 2 0    # L2 up
            echo 1 314 0  # SELECT up
            echo 0 0 0    # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event4
        sleep 1
        killall -15 PPSSPPSDL
        WAS_IN_EMULATOR=0
    elif pgrep "ra32.miyoo" > /dev/null ; then
        {
            echo 1 1 0   # MENU up
            echo 1 57 1  # A down
            echo 1 57 0  # A up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
        killall -q -15 ra32.miyoo
        WAS_IN_EMULATOR=0
    elif pgrep "retroarch" > /dev/null; then
        killall -q -15 retroarch
        WAS_IN_EMULATOR=0
    fi
}

handle_emulator_exit
kill_current_process
update_game_list
sleep 2

#/mnt/SDCARD/spruce/bin/display_text.elf "/mnt/SDCARD/.tmp_update/res/save.png"

# Save brightness and color settings
#cat /sys/devices/virtual/disp/disp/attr/lcdbl >/mnt/SDCARD/.tmp_update/brillo
#cat /sys/devices/virtual/disp/disp/attr/enhance >/mnt/SDCARD/.tmp_update/color

if [ "$WAS_IN_EMULATOR" = 0 ]; then
    /mnt/SDCARD/.tmp_update/scripts/apaga.sh
else
    killall -9 main
    killall -9 runtime.sh
    killall -9 principal.sh
    killall -9 MainUI

    flag_add "save_active"
    log_message "Created save_active flag"

    sync
    log_message "Synced file systems"

    log_message "Shutting down"
    poweroff
fi