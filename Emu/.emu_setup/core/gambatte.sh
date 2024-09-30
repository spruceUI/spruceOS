#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: gambatte-(✓MGBA)"|"Emu Core: (✓GAMBATTE)-mgba"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/gambatte.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mgba.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"gambatte\"|g' "$SYS_OPT"
