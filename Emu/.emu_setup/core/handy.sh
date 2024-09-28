#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: (✓MEDNAFEN)-handy"|"Emu Core: mednafen-(✓HANDY)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/handy.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_lynx.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"handy\"|g' "$SYS_OPT"