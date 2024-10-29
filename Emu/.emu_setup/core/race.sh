#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

display -i "$BG" -t "Core changed to race"

sed -i 's|"Emu Core: race-(✓MEDNAFEN)"|"Emu Core: (✓RACE)-mednafen"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/race.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_ngp.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"race\"|g' "$SYS_OPT"

sleep 2
display_kill
