#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: (✓LUDICROUSN64)-parallel-mupen64plus"|"Emu Core: ludicrousn64-(✓PARALLEL)-mupen64plus"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/km_parallel_n64_xtreme_amped.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mupen64plus.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"km_parallel_n64_xtreme_amped_turbo\"|g' "$SYS_OPT"
