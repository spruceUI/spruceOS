#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

##### DEFINE BASE VARIABLES #####

FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
ROMFILENAME="$(basename "$1")"
GAMENAME="$(echo "$ROMFILENAME" | cut -d'.' -f1)"

log_message "--- Adding favorite game chosen by user ---"

# Construct the new JSON entry
NEW_ENTRY=$(jq -n \
  --arg label "$GAMENAME ($EMU_NAME)" \
  --arg launch "/mnt/SDCARD/Emu/.emu_setup/standard_launch.sh" \
  --arg rompath "/mnt/SDCARD/Emu/$EMU_NAME/../../Roms/$EMU_NAME/$ROMFILENAME" \
  --argjson type "5" \
  '{label: $label, launch: $launch, rompath: $rompath, type: $type}')

# Append new json formatted entry to favourite file
echo "$NEW_ENTRY" >> $FAVOURITE_FILE