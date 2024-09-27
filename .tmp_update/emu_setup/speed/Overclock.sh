#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

if [ "$EMU_NAME" = "DC" ] || [ "$EMU_NAME" = "N64" ]; then
    sed -i 's|"CPU Mode: (✓PERFORMANCE)-Overclock"|"CPU Mode: Performance-(✓OVERCLOCK)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Overclock.sh"|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Performance.sh"|g' "$CONFIG"
else
    sed -i 's|"CPU Mode: Smart-(✓PERFORMANCE)-Overclock"|"CPU Mode: Smart-Performance-(✓OVERCLOCK)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Overclock.sh"|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Smart.sh"|g' "$CONFIG"
fi

sed -i 's|GOV=.*|GOV=\"overclock\"|g' "$SYS_OPT"
