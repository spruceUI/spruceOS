#!/bin/sh
echo $0 $*

PORTS_DIR=/mnt/SDCARD/Roms/PORTS
EMU_DIR="$(dirname "$0")"
GAME="$(basename "$1")"
OVR_DIR="$EMU_DIR/overrides"
OVERRIDE="$OVR_DIR/$GAME.opt"

. "$EMU_DIR/default.opt"
. "$EMU_DIR/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

/mnt/SDCARD/App/utils/utils $GOV $CORES $CPU $GPU $DDR $SWAP

cd $PORTS_DIR
/bin/sh "$1"
