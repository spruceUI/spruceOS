#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to nestopia"

if [ "$EMU_NAME" = "FC" ]; then
    sed -i 's|"Emu Core: (✓FCEUMM)-nestopia-quicknes"|"Emu Core: fceumm-(✓NESTOPIA)-quicknes"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/nestopia.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/quicknes.sh"|g' "$CONFIG"
elif [ "$EMU_NAME" = "FDS" ]; then
    sed -i 's|"Emu Core: (✓FCEUMM)-nestopia"|"Emu Core: fceumm-(✓NESTOPIA)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/nestopia.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/fceumm.sh"|g' "$CONFIG"
fi

sed -i 's|CORE=.*|CORE=\"nestopia\"|g' "$SYS_OPT"

sleep 2
display_kill
