#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# BigPEmu keeps its config under Saves/spruce/bigpemu, seeded once from the
# shipped Emu/JAGUAR/bigpemu/defaultconfigs by bigpemu_functions.sh; this
# puts the shipped file back.
LIVE_CFG="/mnt/SDCARD/Saves/spruce/bigpemu/.bigpemu_userdata/BigPEmuConfig.bigpcfg"
SHIPPED_CFG="/mnt/SDCARD/Emu/JAGUAR/bigpemu/defaultconfigs/BigPEmuConfig.bigpcfg"

log_message "Resetting BigPEmu config to default."
mkdir -p "${LIVE_CFG%/*}"
[ -e "$SHIPPED_CFG" ] && cp -f "$SHIPPED_CFG" "$LIVE_CFG"
[ -e "$SHIPPED_CFG" ] || log_message "Reset BigPEmu config: $SHIPPED_CFG does not exist, nothing restored"
