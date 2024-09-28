#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"


if [ "$EMU_NAME" = "MD" ] || [ "$EMU_NAME" = "SEGACD" ] || [ "$EMU_NAME" = "THIRTYTWOX" ]; then
    sed -i 's|"Emu Core: picodrive-(✓GENESIS+GX)"|"Emu Core: (✓PICODRIVE)-genesis+gx"|g' "$CONFIG"
else
    sed -i 's|"Emu Core: (✓GEARSYSTEM)-picodrive-genesis+gx"|"Emu Core: gearsystem-(✓PICODRIVE)-genesis+gx"|g' "$CONFIG"
fi

sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"picodrive\"|g' "$SYS_OPT"
