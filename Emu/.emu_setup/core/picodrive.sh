#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"
. "$SYS_OPT"

display -i "$BG" -t "Core changed to $CORE"

if [ "$EMU_NAME" = "MD" ] || [ "$EMU_NAME" = "SEGACD" ] || [ "$EMU_NAME" = "THIRTYTWOX" ]; then
    sed -i 's|"Emu Core: picodrive-(✓GENESIS+GX)"|"Emu Core: (✓PICODRIVE)-genesis+gx"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|g' "$CONFIG"
else
    sed -i 's|"Emu Core: (✓GENESIS+GX)-picodrive-gearsystem"|"Emu Core: genesis+gx-(✓PICODRIVE)-gearsystem"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/gearsystem.sh"|g' "$CONFIG"
fi

sed -i 's|CORE=.*|CORE=\"picodrive\"|g' "$SYS_OPT"

sleep 3
display_kill
