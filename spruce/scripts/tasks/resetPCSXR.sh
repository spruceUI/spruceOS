#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

LIVE_CFG=/mnt/SDCARD/Emu/PS/.pcsx/pcsx.cfg
BACKUP_CFG=/mnt/SDCARD/Emu/PS/.pcsx/pcsx.cfg.bak

log_message "Resetting PCSX ReARMed config to default state."
cp -f "$BACKUP_CFG" "$LIVE_CFG"