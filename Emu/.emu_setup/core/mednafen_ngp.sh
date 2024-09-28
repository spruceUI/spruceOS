#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: (✓RACE)-mednafen"|"Emu Core: race-(✓MEDNAFEN)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_ngp.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/race.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"mednafen_lynx\"|g' "$SYS_OPT"