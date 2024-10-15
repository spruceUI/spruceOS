#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

sed -i 's|"Emu Core: uae4arm-(✓PUAE2021)-puae"|"Emu Core: uae4arm-puae2021-(✓PUAE)"|g' "$CONFIG"
sed -i 's|"/mnt/SDCARD/Emu/.emu_setup/core/puae.sh"|"/mnt/SDCARD/Emu/.emu_setup/core/uae4arm.sh"|g' "$CONFIG"
sed -i 's|CORE=.*|CORE=\"puae\"|g' "$SYS_OPT"
