#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

if [ "$EMU_NAME" = "MD" ] || [ "$EMU_NAME" = "SEGACD" ] || [ "$EMU_NAME" = "THIRTYTWOX" ]; then
    sed -i 's|"Emu Core: (✓PICODRIVE)-genesis+gx"|"Emu Core: picodrive-(✓GENESIS+GX)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|g' "$CONFIG"
else
    sed -i 's|"Emu Core: gearsystem-(✓PICODRIVE)-genesis+gx"|"Emu Core: gearsystem-picodrive-(✓GENESIS+GX)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/gearsystem.sh"|g' "$CONFIG"
fi

sed -i 's|CORE=.*|CORE=\"genesis_plus_gx\"|g' "$SYS_OPT"