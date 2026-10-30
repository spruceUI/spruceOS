#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ORIGINAL_NDS_FILE="$(platform_path "/mnt/SDCARD/Emu/NDS/config/drastic-%s.cfg")"
BACKUP_NDS_FILE="$(platform_path "/mnt/SDCARD/Emu/NDS/config/drastic-%s.cfg.bak")"

ORIGINAL_CF2_FILE="/mnt/SDCARD/Emu/NDS/config/drastic.cf2"
BACKUP_CF2_FILE="/mnt/SDCARD/Emu/NDS/config/drastic.cf2.bak"

ORIGINAL_STEWARD_FILE="$(platform_path "/mnt/SDCARD/Emu/NDS/resources/settings_%s.json")"
BACKUP_STEWARD_FILE="$(platform_path "/mnt/SDCARD/Emu/NDS/resources/settings_%s.json.bak")"


log_message "Resetting DraStic config to default."
[ -e "$BACKUP_NDS_FILE" ] && cp -f "$BACKUP_NDS_FILE" "$ORIGINAL_NDS_FILE"
[ -e "$BACKUP_CF2_FILE" ] && cp -f "$BACKUP_CF2_FILE" "$ORIGINAL_CF2_FILE"
[ -e "$BACKUP_STEWARD_FILE" ] && cp -f "$BACKUP_STEWARD_FILE" "$ORIGINAL_STEWARD_FILE"