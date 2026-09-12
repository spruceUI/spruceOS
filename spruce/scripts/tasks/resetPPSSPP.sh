#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ORIGINAL_PPSSPP_FILE="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/ppsspp-$PLATFORM.ini"
ORIGINAL_PPSSPP_CONTROLS_FILE="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM/controls-$PLATFORM.ini"
BACKUP_PPSSPP_FILE="/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM/ppsspp-$PLATFORM.ini"
BACKUP_PPSSPP_CONTROLS_FILE="/mnt/SDCARD/Emu/PSP/default_configs/SYSTEM/controls-$PLATFORM.ini"

log_message "Resetting PPSSPP config to default."
mkdir -p "${ORIGINAL_PPSSPP_FILE%/*}"
[ -e "$BACKUP_PPSSPP_FILE" ] && cp -f "$BACKUP_PPSSPP_FILE" "$ORIGINAL_PPSSPP_FILE"
[ -e "$BACKUP_PPSSPP_FILE" ] || log_message "Reset PPSSPP config: $BACKUP_PPSSPP_FILE does not exist, nothing restored"
[ -e "$BACKUP_PPSSPP_CONTROLS_FILE" ] && cp -f "$BACKUP_PPSSPP_CONTROLS_FILE" "$ORIGINAL_PPSSPP_CONTROLS_FILE"
[ -e "$BACKUP_PPSSPP_CONTROLS_FILE" ] || log_message "Reset PPSSPP config: $BACKUP_PPSSPP_CONTROLS_FILE does not exist, controls not restored"
