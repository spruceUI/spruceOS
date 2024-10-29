#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"
. "$SYS_OPT"

display -i "$BG" -t "Core changed to $CORE"

sed -i 's|"Emu Core: (✓MEDNAFEN)-handy"|"Emu Core: mednafen-(✓HANDY)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/handy.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/mednafen_lynx.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"handy\"|g' "$SYS_OPT"

sleep 3
display_kill
