#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: cap32-(✓CROCODS)"|"Emu Core: (✓CAP32)-crocods"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/cap32.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/crocods.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"cap32\"|g' "$SYS_OPT"
