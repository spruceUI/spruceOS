#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
# Kill keymon
killall -9 keymon
vibrate


BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
SETTINGS_PATH="/mnt/SDCARD/spruce/settings"
LIST_FILE="$SETTINGS_PATH/gs_list"
TEMP_FILE="$FLAG_PATH/gs_list_temp"

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
    elif pgrep "ra32.miyoo" > /dev/null ; then
        {
            echo 1 1 0   # MENU up
            echo 1 57 1  # A down
            echo 1 57 0  # A up
            echo 0 0 0   # tell sendevent to exit
        } | $BIN_PATH/sendevent /dev/input/event3
        killall -q -15 ra32.miyoo
    else
        killall -q -15 retroarch || killall -q -9 MainUI
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

 /mnt/SDCARD/.tmp_update/scripts/apaga.sh
