#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"
. "$SYS_OPT"

display -i "$BG" -t "CPU Mode changed to $MODE"

if [ "$EMU_NAME" = "DC" ] || [ "$EMU_NAME" = "N64" ]; then
    sed -i 's|"CPU Mode: (✓PERFORMANCE)-Overclock"|"CPU Mode: Performance-(✓OVERCLOCK)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/speed/Overclock.sh"|"/mnt/SDCARD/Emu/.emu_setup/speed/Performance.sh"|g' "$CONFIG"
else
    sed -i 's|"CPU Mode: Smart-(✓PERFORMANCE)-Overclock"|"CPU Mode: Smart-Performance-(✓OVERCLOCK)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/speed/Overclock.sh"|"/mnt/SDCARD/Emu/.emu_setup/speed/Smart.sh"|g' "$CONFIG"
fi

sed -i 's|MODE=.*|MODE=\"overclock\"|g' "$SYS_OPT"

sleep 3
display_kill
