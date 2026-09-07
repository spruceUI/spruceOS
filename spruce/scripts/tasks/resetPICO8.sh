#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# PICO-8 rewrites config.txt itself on exit and spruce swaps one of the shipped
# sdl_controllers.* presets over sdl_controllers.txt from its menu option; the
# shipped defaults of both live beside them as .bak.
P8_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"
LIVE_CFG="$P8_DIR/config.txt"
BACKUP_CFG="$P8_DIR/config.txt.bak"
LIVE_PAD="$P8_DIR/sdl_controllers.txt"
BACKUP_PAD="$P8_DIR/sdl_controllers.txt.bak"

log_message "Resetting PICO-8 config to default."
[ -e "$BACKUP_CFG" ] && cp -f "$BACKUP_CFG" "$LIVE_CFG"
[ -e "$BACKUP_CFG" ] || log_message "Reset PICO-8 config: $BACKUP_CFG does not exist, nothing restored"
[ -e "$BACKUP_PAD" ] && cp -f "$BACKUP_PAD" "$LIVE_PAD"
[ -e "$BACKUP_PAD" ] || log_message "Reset PICO-8 config: $BACKUP_PAD does not exist, controller table not restored"
