#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/emu/lib/scummvm_functions.sh

EMU_DIR="/mnt/SDCARD/Emu/SCUMMVM"
LOG_DIR="/mnt/SDCARD/Saves/spruce"

log_message "Scanning for ScummVM games..."
run_scummvm_scan
log_message "ScummVM scan complete."

killall MainUI
