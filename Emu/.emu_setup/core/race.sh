#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: race-(✓MEDNAFEN)"|"Emu Core: (✓RACE)-mednafen"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/race.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_ngp.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"race\"|g' "$SYS_OPT"