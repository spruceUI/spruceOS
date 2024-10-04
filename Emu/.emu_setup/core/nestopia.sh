#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: (✓FCEUMM)-nestopia"|"Emu Core: fceumm-(✓NESTOPIA)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/nestopia.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/fceumm.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"nestopia\"|g' "$SYS_OPT"