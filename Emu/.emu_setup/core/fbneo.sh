#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to fbneo"

if [ "$EMU_NAME" = "ARCADE" ]; then
    sed -i 's|"Emu Core: fbneo-mame2003+-(✓FBALPHA2012)"|"Emu Core: (✓FBNEO)-mame2003+-fbalpha2012"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/fbneo.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mame2003_plus.sh"|g' "$CONFIG"
else
    sed -i 's|"Emu Core: (✓FBALPHA2012)-fbneo"|"Emu Core: fbalpha2012-(✓FBNEO)"|g' "$CONFIG"
    sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/fbneo.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/fbalpha2012.sh"|g' "$CONFIG"
fi
sed -i 's|CORE=.*|CORE=\"fbneo\"|g' "$SYS_OPT"

sleep 3
display_kill
