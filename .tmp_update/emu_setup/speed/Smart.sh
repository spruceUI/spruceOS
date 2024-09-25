#!/bin/sh

EMU_DIR="$(echo "$1" | cut -d'/' -f5)"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"CPU Mode: smart/performance/(OVERCLOCK)"|"CPU Mode: (SMART)/performance/overclock"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Smart.sh"|"/mnt/SDCARD/.tmp_update/emu_setup/speed/Performance.sh"|g' "$CONFIG"
sed -i 's|GOV=.*|GOV=\"conservative\"|g' "$SYS_OPT"
