#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"
. "$SYS_OPT"

display -i "$BG" -t "CPU Mode changed to $MODE"

sed -i 's|"CPU Mode: Smart-Performance-(✓OVERCLOCK)"|"CPU Mode: (✓SMART)-Performance-Overclock"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/speed/Smart.sh"|"/mnt/SDCARD/Emu/.emu_setup/speed/Performance.sh"|g' "$CONFIG"
sed -i 's|MODE=.*|MODE=\"smart\"|g' "$SYS_OPT"

sleep 3
display_kill
