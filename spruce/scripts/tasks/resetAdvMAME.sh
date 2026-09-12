#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# AdvanceMAME keeps advmame.rc under Saves/saves/advmame/<PLATFORM>/.advance,
# seeded once from the shipped Emu/ARCADE/advmame-<PLATFORM>.rc by
# advmame_functions.sh; this puts the shipped file back. Platforms without a
# shipped .rc (AdvanceMAME is not offered there) log and do nothing.
LIVE_RC="/mnt/SDCARD/Saves/saves/advmame/$PLATFORM/.advance/advmame.rc"
SHIPPED_RC="/mnt/SDCARD/Emu/ARCADE/advmame-$PLATFORM.rc"

log_message "Resetting AdvanceMAME config to default."
mkdir -p "${LIVE_RC%/*}"
[ -e "$SHIPPED_RC" ] && cp -f "$SHIPPED_RC" "$LIVE_RC"
[ -e "$SHIPPED_RC" ] || log_message "Reset AdvanceMAME config: $SHIPPED_RC does not exist, nothing restored"
