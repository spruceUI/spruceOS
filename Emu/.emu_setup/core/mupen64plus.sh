#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"
. "$SYS_OPT"

display -i "$BG" -t "Core changed to $CORE"

sed -i 's|"Emu Core: ludicrousn64-(✓PARALLEL)-mupen64plus"|"Emu Core: ludicrousn64-parallel-(✓MUPEN64PLUS)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/mupen64plus.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/km_ludicrousn64_2k22_xtreme_amped.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"mupen64plus\"|g' "$SYS_OPT"

sleep 3
display_kill
