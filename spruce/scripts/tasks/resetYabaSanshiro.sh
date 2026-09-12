#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# YabaSanshiro keeps its pad map in keymapv2.json under Emu/SATURN/.yabasanshiro,
# the tree spruceBackup carries across updates; the shipped default lives
# beside it as .bak. backup.bin in the same directory is the Saturn's battery
# RAM (save data) and is never touched. On the XX platforms the next launch
# seeds the platform's pad entry into the restored file again.
LIVE_KEYMAP="/mnt/SDCARD/Emu/SATURN/.yabasanshiro/keymapv2.json"
BACKUP_KEYMAP="/mnt/SDCARD/Emu/SATURN/.yabasanshiro/keymapv2.json.bak"

log_message "Resetting YabaSanshiro config to default."
[ -e "$BACKUP_KEYMAP" ] && cp -f "$BACKUP_KEYMAP" "$LIVE_KEYMAP"
[ -e "$BACKUP_KEYMAP" ] || log_message "Reset YabaSanshiro config: $BACKUP_KEYMAP does not exist, nothing restored"
