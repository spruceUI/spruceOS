#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: mednafen-(✓HANDY)"|"Emu Core: (✓MEDNAFEN)-handy"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_lynx.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/handy.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"mednafen_lynx\"|g' "$SYS_OPT"