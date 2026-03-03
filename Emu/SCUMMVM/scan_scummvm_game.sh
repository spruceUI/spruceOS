#!/bin/sh
# /mnt/SDCARD/Emu/SCUMMVM/scan_scummvm_game.sh

# Trigger for the smart scan function
export RUN_SCUMMVM_SCAN=true

# Launch the main controller with a dummy argument to satisfy the launcher's logic
exec /mnt/SDCARD/Emu/SCUMMVM/../../spruce/scripts/emu/standard_launch.sh "$@"