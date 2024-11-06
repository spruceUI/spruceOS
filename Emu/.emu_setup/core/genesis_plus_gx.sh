#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to genesis_plus_gx"

if [ "$EMU_NAME" = "MD" ] || [ "$EMU_NAME" = "SEGACD" ]; then
    sed -i 's|"Emu Core: (✓PICODRIVE)-genesis+gx"|"Emu Core: picodrive-(✓GENESIS+GX)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|g' "$CONFIG"
else
    sed -i 's|"Emu Core: genesis+gx-picodrive-(✓GEARSYSTEM)"|"Emu Core: (✓GENESIS+GX)-picodrive-gearsystem"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/picodrive.sh"|g' "$CONFIG"
fi

sed -i 's|CORE=.*|CORE=\"genesis_plus_gx\"|g' "$SYS_OPT"

sleep 2
display_kill
