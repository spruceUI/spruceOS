#!/bin/sh

RA_DIR="/mnt/SDCARD/RetroArch"
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

echo $0 $*

cd "$RA_DIR"
HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"
