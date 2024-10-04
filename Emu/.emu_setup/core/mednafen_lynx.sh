#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: mednafen-(✓HANDY)"|"Emu Core: (✓MEDNAFEN)-handy"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_lynx.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/handy.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"mednafen_lynx\"|g' "$SYS_OPT"