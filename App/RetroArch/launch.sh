#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

RA_DIR=/mnt/SDCARD/RetroArch
cd $RA_DIR/

if [ "$PLATFORM" = "Brick" ]; then
	HOME=$RA_DIR/ $RA_DIR/ra64.trimui -v
elif [ "$PLATFORM" = "A30" ]; then
	HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v
elif [ "$PLATFORM" = "Flip" ]; then
	HOME=$RA_DIR/ $RA_DIR/ra64.miyoo -v
fi

auto_regen_tmp_update