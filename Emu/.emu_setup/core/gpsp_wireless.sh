#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to gpsp_wireless"

sed -i 's|"Emu Core: mgba-(✓GPSP)-gpsp_wireless"|"Emu Core: mgba-gpsp-(✓GPSP_WIRELESS)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/gpsp_wireless.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mgba.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"gpsp_wireless\"|g' "$SYS_OPT"

sleep 2
display_kill
