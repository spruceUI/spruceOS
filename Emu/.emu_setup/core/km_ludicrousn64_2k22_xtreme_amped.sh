#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core:ludicrousn64-(✓MUPEN64PLUS)"|"Emu Core: (✓LUDICROUSN64)-mupen64plus"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/km_ludicrousn64_2k22_xtreme_amped.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mupen64plus.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"km_ludicrousn64_2k22_xtreme_amped\"|g' "$SYS_OPT"
