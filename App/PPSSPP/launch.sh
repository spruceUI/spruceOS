#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/emu/lib/ppsspp_functions.sh

export HOME=/mnt/SDCARD/Saves
export EMU_DIR=/mnt/SDCARD/Emu/PSP/
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR"

unset ROM_FILE
LOG_DIR="/mnt/SDCARD/Saves/spruce"
CORE="PPSSPP-SA"

cd $EMU_DIR

move_dotconfig_into_place

run_ppsspp

auto_regen_tmp_update
