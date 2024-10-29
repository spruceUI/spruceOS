#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to snes9x"

sed -i 's|"Emu Core: chimerasnes-(✓SUPAFAUST)-snes9x"|"Emu Core: chimerasnes-supafaust-(✓SNES9X)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/snes9x.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/chimerasnes.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"snes9x\"|g' "$SYS_OPT"

sleep 3
display_kill
