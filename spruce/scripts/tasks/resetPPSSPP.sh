#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ORIGINAL_PPSSPP_FILE="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/ppsspp-$PLATFORM.ini"
ORIGINAL_PPSSPP_CONTROLS_FILE="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/controls-$PLATFORM.ini"

BACKUP_PPSSPP_FILE="/mnt/SDCARD/Emu/.emu_setup/.config/ppsspp/PSP/SYSTEM/ppsspp-$PLATFORM.ini"
BACKUP_PPSSPP_CONTROLS_FILE="/mnt/SDCARD/Emu/.emu_setup/.config/ppsspp/PSP/SYSTEM/controls-$PLATFORM.ini"

log_message "Resetting PPSSPP config to default."
cp -f "$BACKUP_PPSSPP_FILE" "$ORIGINAL_PPSSPP_FILE"
cp -f "$BACKUP_PPSSPP_CONTROLS_FILE" "$ORIGINAL_PPSSPP_CONTROLS_FILE"
