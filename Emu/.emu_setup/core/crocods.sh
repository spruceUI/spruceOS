#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to crocods"

sed -i 's|"Emu Core: (✓CAP32)-crocods"|"Emu Core: cap32-(✓CROCODS)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/crocods.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/cap32.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"crocods\"|g' "$SYS_OPT"

sleep 2
display_kill
