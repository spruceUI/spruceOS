#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Flycast standalone keeps its config in Emu/DC/config (XDG_CONFIG_HOME), the
# tree spruceBackup carries across updates, so the shipped defaults live
# beside it as .bak. The pad mapping is restored too: flycast rewrites it when
# a control is remapped in its menu.
LIVE_CFG="/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg"
BACKUP_CFG="/mnt/SDCARD/Emu/DC/config/flycast/emu.cfg.bak"
LIVE_MAP="/mnt/SDCARD/Emu/DC/config/flycast/mappings/SDL_Xbox 360 Controller.cfg"
BACKUP_MAP="/mnt/SDCARD/Emu/DC/config/flycast/mappings/SDL_Xbox 360 Controller.cfg.bak"

log_message "Resetting Flycast standalone config to default."
[ -e "$BACKUP_CFG" ] && cp -f "$BACKUP_CFG" "$LIVE_CFG"
[ -e "$BACKUP_CFG" ] || log_message "Reset Flycast config: $BACKUP_CFG does not exist, nothing restored"
[ -e "$BACKUP_MAP" ] && cp -f "$BACKUP_MAP" "$LIVE_MAP"
[ -e "$BACKUP_MAP" ] || log_message "Reset Flycast config: $BACKUP_MAP does not exist, mapping not restored"
