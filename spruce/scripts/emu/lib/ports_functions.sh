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
/mnt/SDCARD/spruce/scripts/asound-setup.sh /mnt/SDCARD/Saves/flip/home
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
    rm "$PM_DIR/gamecontrollerdb.txt"
	PORT_CONTROL="$(jq -r '.menuOptions.controlMode.selected' "$EMU_JSON_PATH")"
    if [ "$PORT_CONTROL" = "X360" ]; then
        cp "/mnt/SDCARD/Emu/PORTS/gamecontrollerdb_360.txt" "$PM_DIR/gamecontrollerdb.txt"
    else
        cp "/mnt/SDCARD/Emu/PORTS/gamecontrollerdb_nintendo.txt" "$PM_DIR/gamecontrollerdb.txt"
    fi
}

run_port() {
    log_message "Running port on $PLATFORM w/ ($PLATFORM_ARCHITECTURE)"
    device_prepare_for_ports_run

    # Setup variables
    PORTS_DIR=/mnt/SDCARD/Roms/PORTS
    export HOME="/mnt/SDCARD/Saves/flip/home"
    export LD_LIBRARY_PATH="$PORTS_LD_LIBRARY_PATH:$LD_LIBRARY_PATH"
	export LC_ALL=C
    # TODO: Remove this when portmaster updates spruce detection
    if [ "$PLATFORM" = "Pixel2" ]; then
        PM_DIR="/mnt/SDCARD/Roms/PORTS/PortMaster"
        MOUNT_BIND=false
    else
        PM_DIR="/mnt/SDCARD/Persistent/portmaster/PortMaster"
        MOUNT_BIND=true
        export PATH="/mnt/SDCARD/spruce/flip/bin/:$PATH"
    fi

    set_port_mode
    is_retroarch_port
    if [ $? -eq 1 ]; then
        log_message "Launching RA port $ROM_FILE"
        cd /mnt/SDCARD/RetroArch/
        "$ROM_FILE" &> /mnt/SDCARD/Saves/spruce/port.log &
    else
        if [ "$MOUNT_BIND" = true ]; then
            mount --bind /mnt/SDCARD/Persistent/portmaster/bin/python3.10 /mnt/SDCARD/Persistent/portmaster/bin/python
        fi

        log_message "PORTS_DIR: $PORTS_DIR, HOME=$HOME, LD_LIBRARY_PATH=$LD_LIBRARY_PATH, PATH=$PATH"
        setsid "$ROM_FILE" &> /mnt/SDCARD/Saves/spruce/port.log &
        SID=$!
        echo "$SID" > /tmp/last_port_sid
        wait "$SID"
        rm -f /tmp/last_port_sid
    fi

    device_cleanup_after_ports_run
}

run_A30_port() {

    # ensure correct RA bin and config are available
    . /mnt/SDCARD/spruce/scripts/emu/lib/ra_functions.sh
    touch /mnt/SDCARD/RetroArch/retroarch
    mount --bind /mnt/SDCARD/RetroArch/retroarch.A30 /mnt/SDCARD/RetroArch/retroarch
    prepare_ra_config 2>/dev/null

    # make A30PORTS accessible from PORTS for backwards compatibility
    mkdir -p /mnt/SDCARD/Roms/PORTS
    mount --bind /mnt/SDCARD/Roms/A30PORTS /mnt/SDCARD/Roms/PORTS

    # launch the actual game
    cd /mnt/SDCARD/Roms/A30PORTS
    /bin/sh "$ROM_FILE" 

    # clean up and back up any RA config modifications
    umount /mnt/SDCARD/Roms/PORTS
    umount /mnt/SDCARD/RetroArch/retroarch
    backup_ra_config 2>/dev/null
}
