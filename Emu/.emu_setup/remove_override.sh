#!/bin/sh

##### DEFINE BASE VARIABLES #####

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "--- Removing per-game launch options ---"

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
GAME="$(basename "$1")"
OPT_DIR="/mnt/SDCARD/Emu/.emu_setup/options"
OVR_DIR="/mnt/SDCARD/Emu/.emu_setup/overrides"
OPT_FILE="$OPT_DIR/${EMU_NAME}.opt"
OVR_FILE="$OVR_DIR/$EMU_NAME/$GAME.opt"

##### IMPORT .OPT FILES #####
if [ -f "$OVR_FILE" ]; then
	rm -f "$OVR_FILE"
	log_message "Launch setting override removed for $GAME."
else
	log_message "No override file to delete for $GAME."
fi
display -d 2 -t "Removed launch override from $GAME"