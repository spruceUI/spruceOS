#!/bin/sh


get_python_path() {
    echo "/mnt/SDCARD/spruce/flip/bin/python3.10"
}

send_menu_button_to_retroarch() {
    if pgrep "ra32.miyoo" >/dev/null; then
        send_virtual_key_L3
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