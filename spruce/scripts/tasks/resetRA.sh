#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh



log_message "Resetting RetroArch config to default."
# Every platform, the XX line included, resets from its own shipped .bak. The
# .bak is not in the backup list, so it always arrives fresh with the payload
# and is the way back from a per-platform cfg that a restore carried over.
ORIGINAL_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
BACKUP_RA_FILE="/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg.bak"
[ -e "$BACKUP_RA_FILE" ] && cp -f "$BACKUP_RA_FILE" "$ORIGINAL_RA_FILE"
[ -e "$BACKUP_RA_FILE" ] || log_message "Reset RetroArch config: $BACKUP_RA_FILE does not exist, nothing restored"

