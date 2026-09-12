#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# ScummVM keeps a per-platform-family scummvm.ini under Saves/.config, seeded
# once from Emu/SCUMMVM/.config by scummvm_functions.sh; this puts the shipped
# file back. The same mapping as _set_scummvm_platform, kept literal here so
# the task does not source a launcher with side effects. The ini also holds
# the scanned game list, so run "Scan ScummVM games" afterwards.
case "$PLATFORM" in
    "Flip")       SCUMMVM_TARGET="flip" ;;
    "SmartPro")   SCUMMVM_TARGET="tsp" ;;
    "SmartProS")  SCUMMVM_TARGET="tsps" ;;
    "Brick")      SCUMMVM_TARGET="brick" ;;
    "BrickPro")   SCUMMVM_TARGET="brickpro" ;;
    "Pixel2")     SCUMMVM_TARGET="pixel2" ;;
    "Anbernic"*)  SCUMMVM_TARGET="anbernic" ;;
    "A30")        SCUMMVM_TARGET="a30" ;;
    "MiyooMini")  SCUMMVM_TARGET="mini" ;;
    *)            SCUMMVM_TARGET="flip" ;;
esac
LIVE_INI="/mnt/SDCARD/Saves/.config/scummvm-$SCUMMVM_TARGET/scummvm.ini"
SHIPPED_INI="/mnt/SDCARD/Emu/SCUMMVM/.config/scummvm-$SCUMMVM_TARGET/scummvm.ini"

log_message "Resetting ScummVM config to default ($SCUMMVM_TARGET)."
mkdir -p "${LIVE_INI%/*}"
[ -e "$SHIPPED_INI" ] && cp -f "$SHIPPED_INI" "$LIVE_INI"
[ -e "$SHIPPED_INI" ] || log_message "Reset ScummVM config: $SHIPPED_INI does not exist, nothing restored"
