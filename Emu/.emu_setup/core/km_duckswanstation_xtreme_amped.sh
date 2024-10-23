#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: (✓PCSX_REARMED)-duckswanstation"|"Emu Core: pcsx_rearmed-(✓DUCKSWANSTATION)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/km_duckswanstation_xtreme_amped.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/pcsx_rearmed.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"km_duckswanstation_xtreme_amped\"|g' "$SYS_OPT"