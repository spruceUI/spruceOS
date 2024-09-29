#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: chimerasnes-(✓SUPAFAUST)-snes9x"|"Emu Core: chimerasnes-supafaust-(✓SNES9X)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/snes9x.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/chimerasnes.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"snes9x\"|g' "$SYS_OPT"