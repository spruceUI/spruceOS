#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: gearsystem-picodrive-(✓GENESIS+GX)"|"Emu Core: (✓GEARSYSTEM)-picodrive-genesis+gx"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/gearsystem.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"gearsystem\"|g' "$SYS_OPT"
