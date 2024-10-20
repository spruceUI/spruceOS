#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: chimerasnes-supafaust-(✓SNES9X)"|"Emu Core: (✓CHIMERASNES)-supafaust-snes9x"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/chimerasnes.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_supafaust.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"chimerasnes\"|g' "$SYS_OPT"
