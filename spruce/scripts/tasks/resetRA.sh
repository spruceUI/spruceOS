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

# The XX line's pad autoconfigs are a shipped default set too, one pair per
# pad layout; put this layout's pair back the same way the launcher does.
case "$PLATFORM" in
    "Anbernic"*)
        for drv in sdl2 linuxraw; do
            XX_AC_SRC="/mnt/SDCARD/RetroArch/platform/autoconfig-xx/${XX_PAD_LAYOUT:-2stick}/$drv/ANBERNIC-keys.cfg"
            XX_AC_DST="/mnt/SDCARD/RetroArch/.retroarch/autoconfig/$drv/ANBERNIC-keys.cfg"
            mkdir -p "${XX_AC_DST%/*}"
            [ -e "$XX_AC_SRC" ] && cp -f "$XX_AC_SRC" "$XX_AC_DST"
            [ -e "$XX_AC_SRC" ] || log_message "Reset RetroArch config: $XX_AC_SRC does not exist, autoconfig not restored"
        done
        ;;
esac
