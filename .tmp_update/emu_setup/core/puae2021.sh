#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: puae2021-puae-(✓UAE4ARM)"|"Emu Core: (✓PUAE2021)-puae-uae4arm"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/.tmp_update/emu_setup/core/puae2021.sh"|"/mnt/SDCARD/.tmp_update/emu_setup/core/puae.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"puae2021\"|g' "$SYS_OPT"