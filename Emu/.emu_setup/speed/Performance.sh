#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

if [ "$EMU_NAME" = "DC" ] || [ "$EMU_NAME" = "N64" ]; then
    sed -i 's|"CPU Mode: Performance-(✓OVERCLOCK)"|"CPU Mode: (✓PERFORMANCE)-Overclock"|g' "$CONFIG"
else
    sed -i 's|"CPU Mode: (✓SMART)-Performance-Overclock"|"CPU Mode: Smart-(✓PERFORMANCE)-Overclock"|g' "$CONFIG"
fi

sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/speed/Performance.sh"|"/mnt/SDCARD/Emu/.emu_setup/speed/Overclock.sh"|g' "$CONFIG"
sed -i 's|GOV=.*|GOV=\"performance\"|g' "$SYS_OPT"
