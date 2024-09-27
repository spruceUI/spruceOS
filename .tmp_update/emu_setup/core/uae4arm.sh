#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

sed -i 's|"Emu Core: puae2021-(✓PUAE)-uae4arm"|"Emu Core: puae2021-puae-(✓UAE4ARM)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/.tmp_update/emu_setup/core/uae4arm.sh"|"/mnt/SDCARD/.tmp_update/emu_setup/core/puae2021.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"uae4arm\"|g' "$SYS_OPT"