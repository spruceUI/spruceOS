#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: (✓FBNEO)-mame2003+-fbalpha2012"|"Emu Core: fbneo-(✓MAME2003+)-fbalpha2012"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mame2003_plus.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/fbalpha2012.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"mame2003_plus\"|g' "$SYS_OPT"