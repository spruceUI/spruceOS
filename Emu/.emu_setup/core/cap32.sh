#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: cap32-(✓CROCODS)"|"Emu Core: (✓CAP32)-crocods"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/cap32.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/crocods.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"cap32\"|g' "$SYS_OPT"
