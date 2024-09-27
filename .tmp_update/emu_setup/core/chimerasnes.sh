#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: chimerasnes-supafaust-(✓SNES9X)"|"Emu Core: (✓CHIMERASNES)-supafaust-snes9x"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/.tmp_update/emu_setup/core/chimerasnes.sh"|"/mnt/SDCARD/.tmp_update/emu_setup/core/mednafen_supafaust.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"chimerasnes\"|g' "$SYS_OPT"
