#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

if [ "$EMU_NAME" = "DC" ]; then
    sed -i 's|"CPU Mode: Performance-(✓OVERCLOCK)"|"CPU Mode: (✓PERFORMANCE)-Overclock"|g' "$CONFIG"
else
    sed -i 's|"CPU Mode: (✓SMART)-Performance-Overclock"|"CPU Mode: Smart-(✓PERFORMANCE)-Overclock"|g' "$CONFIG"
fi

sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/speed/Performance.sh"|"/mnt/SDCARD/Emu/.emu_setup/speed/Overclock.sh"|g' "$CONFIG"
sed -i 's|MODE=.*|MODE=\"performance\"|g' "$SYS_OPT"
