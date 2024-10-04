#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: gearsystem-picodrive-(✓GENESIS+GX)"|"Emu Core: (✓GEARSYSTEM)-picodrive-genesis+gx"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/gearsystem.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"gearsystem\"|g' "$SYS_OPT"
