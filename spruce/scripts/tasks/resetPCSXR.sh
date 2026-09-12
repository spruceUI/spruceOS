#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LIVE_CFG="/mnt/SDCARD/Emu/PS/.pcsx/pcsx.cfg"
BACKUP_CFG="/mnt/SDCARD/Emu/PS/.pcsx/pcsx.cfg.bak"

log_message "Resetting PCSX ReARMed config to default state."
[ -e "$BACKUP_CFG" ] && cp -f "$BACKUP_CFG" "$LIVE_CFG"
[ -e "$BACKUP_CFG" ] || log_message "Reset PCSX ReARMed config: $BACKUP_CFG does not exist, nothing restored"
