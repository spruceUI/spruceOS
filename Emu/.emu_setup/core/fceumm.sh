#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: fceumm-(✓NESTOPIA)"|"Emu Core: (✓FCEUMM)-nestopia"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/fceumm.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/nestopia.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"fceumm\"|g' "$SYS_OPT"
