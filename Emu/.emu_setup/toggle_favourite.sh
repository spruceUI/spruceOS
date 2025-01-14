#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

##### DEFINE BASE VARIABLES #####

FAVOURITE_FILE="/mnt/SDCARD/Roms/favourite.json"
EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
ROMFILENAME="$(basename "$1")"
GAMELIST_FILE="/mnt/SDCARD/Roms/$EMU_NAME/miyoogamelist.xml"
ROM_PATH="$1"
BG="/mnt/SDCARD/spruce/imgs/bg_tree.png"

# Get game name first - we'll need it either way
if [ -f "$GAMELIST_FILE" ]; then
    # Extract filename without path and extension for matching
    ROM_PATH_MATCH="./$(basename "$ROMFILENAME")"
    # Use grep to find the game entry and extract the name, and trim whitespace
    GAMENAME=$(grep -A 2 "<path>$ROM_PATH_MATCH</path>" "$GAMELIST_FILE" | grep "<name>" | sed 's/<name>\(.*\)<\/name>/\1/' | sed 's/^[ \t]*//;s/[ \t]*$//')
    # If no name found in gamelist, fall back to filename
    if [ -z "$GAMENAME" ]; then
        GAMENAME="$(echo "$ROMFILENAME" | cut -d'.' -f1)"
    fi
else
    GAMENAME="$(echo "$ROMFILENAME" | cut -d'.' -f1)"
fi

# Check if ROM is already in favourites
if grep -q "\"rompath\":\"$ROM_PATH\"" "$FAVOURITE_FILE"; then
    # Create a temporary file without the matching entry
    grep -v "\"rompath\":\"$ROM_PATH\"" "$FAVOURITE_FILE" > "$FAVOURITE_FILE.tmp"
    # Replace the original file
    mv "$FAVOURITE_FILE.tmp" "$FAVOURITE_FILE"
    log_message "Removed $GAMENAME from favourite.json via X menu"
    display -i "$BG" -t "$GAMENAME removed from favorites" -d 2
else
    log_message "Added $GAMENAME ($EMU_NAME) to favourite.json via X menu"

    # Construct the new JSON entry
    NEW_ENTRY=$(jq -n \
      --arg label "$GAMENAME ($EMU_NAME)" \
      --arg launch "/mnt/SDCARD/Emu/$EMU_NAME/../.emu_setup/standard_launch.sh" \
      --arg rompath "$ROM_PATH" \
      --argjson type "5" \
      '{label: $label, launch: $launch, rompath: $rompath, type: $type}')

    # Append new json formatted entry to favourite file
    echo "$NEW_ENTRY" >> "$FAVOURITE_FILE"
    display -i "$BG" -t "$GAMENAME added to favorites" -d 2
fi

