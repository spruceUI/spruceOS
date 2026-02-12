#!/bin/sh


get_python_path() {
    echo "/mnt/SDCARD/spruce/flip/bin/python3.10"
}

send_virtual_key_L3R3() {
    {
        echo $B_MENU 0 # MENU up
        echo $B_L3 1 # L3 down
        echo $B_R3 1 # R3 down
        sleep 0.1
        echo $B_R3 0 # R3 up
        echo $B_L3 0 # L3 up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP
}

send_menu_button_to_retroarch() {
    if pgrep "ra32.miyoo" >/dev/null; then
        send_virtual_key_L3
    elif pgrep "retroarch.trimui" >/dev/null; then
        send_virtual_key_L3R3
    elif pgrep "ra64.trimui_$PLATFORM" >/dev/null || pgrep "ra64.miyoo" >/dev/null; then
        echo "MENU_TOGGLE" | netcat -u -w0.1 127.0.0.1 55355
    elif pgrep -f "retroarch" >/dev/null; then
        echo "MENU_TOGGLE" | netcat -u -w0.1 127.0.0.1 55355
    elif pgrep -f "PPSSPPSDL" >/dev/null; then
        send_virtual_key_L3
    fi
    # PICO8 has no in-game menu and
    # NDS has 2 in-game menus that are activated by hotkeys with menu button short tap
}

get_sftp_service_name() {
    echo "sftpgo"
}

get_ssh_service_name() {
    echo "dropbearmulti"
}


close_ppsspp_menu() {

    if pgrep -f "PPSSPPSDL" >/dev/null; then
        log_message "homebutton_watchdog.sh: Closing PPSSPP menu."
        # use sendevent to send SELECT + R1 combo buttons to PPSSPP
        {
            echo $B_RIGHT 1  
            echo $B_RIGHT 0  
            echo $B_A 1  
            echo $B_A 0  
        } > /tmp/ppsspp_events.txt


        # run sendevent in a fully detached subshell
        (
            sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP < /tmp/ppsspp_events.txt
        ) < /dev/null > /dev/null 2>&1 &

        sleep 0.5
    fi
}
