#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: (✓MGBA)-gpsp"|"Emu Core: mgba-(✓GPSP)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/gpsp.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mgba.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"gpsp\"|g' "$SYS_OPT"
