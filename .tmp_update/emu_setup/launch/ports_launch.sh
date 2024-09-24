#!/bin/sh
echo $0 $*

export PORTS_DIR=/mnt/SDCARD/Roms/PORTS
export EMU_DIR="$(dirname "$0")"
export GAME="$(basename "$1")"
export OVR_DIR="$EMU_DIR/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"

. "$EMU_DIR/default.opt"
. "$EMU_DIR/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

/mnt/SDCARD/App/utils/utils "conservative" 4 1344 384 1080 1

cd $PORTS_DIR
/bin/sh "$1"
