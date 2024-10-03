#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: mupen64plus-(✓LUDICROUSN64)"|"Emu Core: (✓MUPEN64PLUS)-ludicrousn64"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mupen64plus.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/km_ludicrousn64_xtreme_amped.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"mupen64plus\"|g' "$SYS_OPT"
