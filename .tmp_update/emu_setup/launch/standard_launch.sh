#!/bin/sh

export RA_DIR="/mnt/SDCARD/RetroArch"
export EMU_DIR="$(dirname "$0")"
export GAME="$(basename "$1")"
export OVR_DIR="$EMU_DIR/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"

. "$EMU_DIR/default.opt"
. "$EMU_DIR/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

/mnt/SDCARD/App/utils/utils $GOV $CORES $CPU $GPU $DDR $SWAP
/mnt/SDCARD/.tmp_update/scripts/gs_listener.sh &
echo $0 $*

cd "$RA_DIR"
HOME="$RA_DIR/" "$RA_DIR/$RA_BIN" -v -L "$RA_DIR/.retroarch/cores/${CORE}_libretro.so" "$1"
if [ -f "/mnt/SDCARD/.tmp_update/flags/gs_activated" ]; then
	"/mnt/SDCARD/.tmp_update/scripts/gs.sh"
fi
