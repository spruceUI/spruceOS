#!/bin/sh

. "/mnt/SDCARD/spruce/scripts/platform/common.sh"


get_python_path() {
    echo "/mnt/SDCARD/spruce/flip/bin/python3.10"
}

get_qr_bin_path() {
    echo "/mnt/SDCARD/spruce/bin64/qrencode"
}


set_path_variable() {
    export PATH="/mnt/SDCARD/spruce/bin64:$PATH"
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


set_dark_httpd_dir() {
    DARKHTTPD_DIR=/mnt/SDCARD/spruce/bin64/darkhttpd
}

set_SMB_DIR(){
   SMB_DIR=/mnt/SDCARD/spruce/bin64/Samba
}

set_LD_LIBRARY_PATH_FOR_SAMBA(){
	LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/mnt/SDCARD/spruce/flip/lib"
}

set_SFTPGO_DIR() {
    SFTPGO_DIR="/mnt/SDCARD/spruce/bin64/SFTPGo"
}

set_syncthing_ST_BIN() {
    ST_BIN=/mnt/SDCARD/spruce/bin64/Syncthing/bin/syncthing
}
