#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

if [ "$EMU_NAME" = "ARCADE" ]; then
    sed -i 's|"Emu Core: fbneo-(✓MAME2003+)-fbalpha2012"|"Emu Core: fbneo-mame2003+-(✓FBALPHA2012)"|g' "$CONFIG"
else
    sed -i 's|"Emu Core: fbalpha2012-(✓FBNEO)"|"Emu Core: (✓FBALPHA2012)-fbneo"|g' "$CONFIG"
fi
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/fbalpha2012.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/fbneo.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"fbalpha2012\"|g' "$SYS_OPT"