#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"CPU Mode: smart-(✓PERFORMANCE)-overclock"|"CPU Mode: smart-performance-(✓OVERCLOCK)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Overclock.sh"|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Smart.sh"|g' "$CONFIG"
sed -i 's|GOV=.*|GOV=\"overclock\"|g' "$SYS_OPT"
