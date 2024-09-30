#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

if [ "$EMU_NAME" = "GB" ] || [ "$EMU_NAME" = "GBC" ]; then
    sed -i 's|"Emu Core: (✓GAMBATTE)-mgba"|"Emu Core: gambatte-(✓MGBA)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mgba.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/gambatte.sh"|g' "$CONFIG"
else
    sed -i 's|"Emu Core: mgba-(✓GPSP)"|"Emu Core: (✓MGBA)-gpsp"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mgba.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/gpsp.sh"|g' "$CONFIG"
fi
sed -i 's|CORE=.*|CORE=\"mgba\"|g' "$SYS_OPT"
