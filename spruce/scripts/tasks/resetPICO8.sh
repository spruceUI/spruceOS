#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# PICO-8 rewrites config.txt itself on exit and spruce swaps one of the shipped
# sdl_controllers.* presets over sdl_controllers.txt from its menu option.
P8_DIR="/mnt/SDCARD/Saves/.lexaloffle/pico-8"
SEED_DIR="/mnt/SDCARD/Emu/PICO8/.lexaloffle/pico-8"

LIVE_CFG="$P8_DIR/config.txt"
BACKUP_CFG="$SEED_DIR/config.txt"


log_message "Resetting PICO-8 config to default."
mkdir -p "$P8_DIR"
[ -e "$BACKUP_CFG" ] && cp -f "$BACKUP_CFG" "$LIVE_CFG"
[ -e "$BACKUP_CFG" ] || log_message "Reset PICO-8 config: $BACKUP_CFG does not exist, nothing restored"
