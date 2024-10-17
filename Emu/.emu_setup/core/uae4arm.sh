#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: uae4arm-(✓PUAE2021)"|"Emu Core: (✓UAE4ARM)-puae2021"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/uae4arm.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/puae2021.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"uae4arm\"|g' "$SYS_OPT"