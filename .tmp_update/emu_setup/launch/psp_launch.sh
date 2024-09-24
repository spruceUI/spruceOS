#!/bin/sh

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
cd $EMU_DIR
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EMU_DIR

echo "=============================================="
echo "==================== PPSSPP  ================="
echo "=============================================="

export HOME=/mnt/SDCARD
./miyoo282_xpad_inputd&
./PPSSPPSDL "$*"
killall miyoo282_xpad_inputd
