#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: (✓MUPEN64PLUS)-ludicrousn64"|"Emu Core: mupen64plus-(✓LUDICROUSN64)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/km_ludicrousn64_xtreme_amped.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mupen64plus.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"km_ludicrousn64_xtreme_amped\"|g' "$SYS_OPT"
