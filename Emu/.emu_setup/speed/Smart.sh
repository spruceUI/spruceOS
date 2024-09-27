#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"CPU Mode: Smart-Performance-(✓OVERCLOCK)"|"CPU Mode: (✓SMART)-Performance-Overclock"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/speed/Smart.sh"|"/mnt/SDCARD/Emu/.emu_setup/speed/Performance.sh"|g' "$CONFIG"
sed -i 's|GOV=.*|GOV=\"conservative\"|g' "$SYS_OPT"
