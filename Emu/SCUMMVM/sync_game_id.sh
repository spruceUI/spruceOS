#!/bin/sh
# /mnt/SDCARD/Emu/SCUMMVM/sync_game_id.sh

# Trigger for sync game id
export SYNC_GAME_ID=true

# Launch the main controller with a dummy argument to satisfy the launcher's logic
exec /mnt/SDCARD/Emu/SCUMMVM/../../spruce/scripts/emu/standard_launch.sh "$@"