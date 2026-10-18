#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# mupen64plus standalone. Its main config (video plugin, input mode, the
# overlay menu's settings) is mupen64plus.cfg under the emulator dir the
# platform cfg names in MUPEN_DIR; the shipped default lives beside it as
# .bak. InputAutoCfg.ini is mupen's pad table: a board that ships its own under
# pad/ gets that one back (the launcher copies it into place anyway), any other
# restores the shipped .bak.
MUPEN_HOME="/mnt/SDCARD/Emu/N64/${MUPEN_DIR:-mupen64plus}"
LIVE_CFG="$MUPEN_HOME/.config/mupen64plus/mupen64plus.cfg"
BACKUP_CFG="$MUPEN_HOME/.config/mupen64plus/mupen64plus.cfg.bak"
LIVE_AC="$MUPEN_HOME/InputAutoCfg.ini"
BACKUP_AC="$MUPEN_HOME/pad/InputAutoCfg-${MUPEN_PAD_TABLE:-$PLATFORM}.ini"
[ -f "$BACKUP_AC" ] || BACKUP_AC="$MUPEN_HOME/InputAutoCfg.ini.bak"

log_message "Resetting mupen64plus config to default."
[ -e "$BACKUP_CFG" ] && cp -f "$BACKUP_CFG" "$LIVE_CFG"
[ -e "$BACKUP_CFG" ] || log_message "Reset mupen64plus config: $BACKUP_CFG does not exist, nothing restored"
[ -e "$BACKUP_AC" ] && cp -f "$BACKUP_AC" "$LIVE_AC"
[ -e "$BACKUP_AC" ] || log_message "Reset mupen64plus config: $BACKUP_AC does not exist, pad table not restored"
