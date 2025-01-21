#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

RA_DIR=/mnt/SDCARD/RetroArch
cd $RA_DIR/

case "$PLATFORM" in
	"A30") RA_BIN="ra32.miyoo" ;;
	"Flip") RA_BIN="ra64.miyoo" ;;
	"Brick"|"SmartPro") RA_BIN="ra64.trimui_$PLATFORM" ;;
esac

HOME=$RA_DIR/ $RA_DIR/$RA_BIN -v

auto_regen_tmp_update