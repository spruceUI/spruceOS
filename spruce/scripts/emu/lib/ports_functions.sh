#!/bin/sh

# Requires globals:
#   ROM_FILE
#   PLATFORM
#   EMU_JSON_PATH
#   LD_LIBRARY_PATH
#   PATH
#
# Provides:
#   extract_game_dir
#   is_retroarch_port
#   set_port_mode
#   run_port

extract_game_dir(){
    # long-term come up with better method.
    # this is short term for testing
    gamedir_line=$(grep "^GAMEDIR=" "$ROM_FILE")
    # If gamedir_name ends with a slash, remove the slash
    gamedir_line="${gamedir_line%/}"
    # Extract everything after the last '/' in the GAMEDIR line and assign it to game_dir
    game_dir="/mnt/SDCARD/Roms/PORTS/${gamedir_line##*/}"
    # If game_dir ends with a quote, remove the quote
    echo "${game_dir%\"}"
}

is_retroarch_port() {
    # Check if the file contains "retroarch"
    if grep -q "retroarch" "$ROM_FILE"; then
        return 1;
    else
        return 0;
    fi
}

set_port_mode() {
    rm "/mnt/SDCARD/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
	PORT_CONTROL="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
    if [ "$PORT_CONTROL" = "X360" ]; then
        cp "/mnt/SDCARD/Emu/PORTS/gamecontrollerdb_360.txt" "/mnt/SDCARD/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
    else
        cp "/mnt/SDCARD/Emu/PORTS/gamecontrollerdb_nintendo.txt" "/mnt/SDCARD/Persistent/portmaster/PortMaster/gamecontrollerdb.txt"
    fi
}

run_port() {
    log_message "Running port on $PLATFORM w/ ($PLATFORM_ARCHITECTURE)"
    device_prepare_for_ports_run
	
	
    if [ "$PLATFORM_ARCHITECTURE" == "aarch64" ]; then
        set_port_mode

        is_retroarch_port
        PORTS_DIR=/mnt/SDCARD/Roms/PORTS
        export HOME="/mnt/SDCARD/Saves/flip/home"
        export LD_LIBRARY_PATH="$PORTS_LD_LIBRARY_PATH:$LD_LIBRARY_PATH"
        export PATH="/mnt/SDCARD/spruce/flip/bin/:$PATH"
        if [ $? -eq 1 ]; then
            log_message "Launching RA port $ROM_FILE"
            cd /mnt/SDCARD/RetroArch/
            "$ROM_FILE" &> /mnt/SDCARD/Saves/spruce/port.log &
        else
            log_message "PORTS_DIR: $PORTS_DIR, HOME=$HOME, LD_LIBRARY_PATH=$LD_LIBRARY_PATH, PATH=$PATH"
            setsid "$ROM_FILE" &> /mnt/SDCARD/Saves/spruce/port.log &
            SID=$!
            echo "$SID" > /tmp/last_port_sid
            wait "$SID"
            rm -f /tmp/last_port_sid
        fi
        
    else
        PORTS_DIR=/mnt/SDCARD/Roms/PORTS
        cd $PORTS_DIR
        /bin/sh "$ROM_FILE" 
    fi

    device_cleanup_after_ports_run
}