#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to gearsystem"

if [ "$EMU_NAME" = "MS" ] || [ "$EMU_NAME" = "GG" ]; then
    sed -i 's|"Emu Core: genesis+gx-(✓PICODRIVE)-gearsystem"|"Emu Core: genesis+gx-picodrive-(✓GEARSYSTEM)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/gearsystem.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|g' "$CONFIG"
elif [ "$EMU_NAME" = "SEGASGONE" ]; then
    sed -i 's|"Emu Core: genesis+gx-(✓BLUEMSX)-gearsystem"|"Emu Core: genesis+gx-bluemsx-(✓GEARSYSTEM)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/gearsystem.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/genesis_plus_gx.sh"|g' "$CONFIG"
fi

sed -i 's|CORE=.*|CORE=\"gearsystem\"|g' "$SYS_OPT"

sleep 2
display_kill
