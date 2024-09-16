#!/bin/sh
mydir=`dirname "$0"`

export HOME=$mydir
export PATH=$mydir/bin:$PATH
export LD_LIBRARY_PATH=$mydir/libs:/usr/miyoo/lib:/usr/lib:$LD_LIBRARY_PATH

export GAME="$(basename "$1")"
export OVR_DIR="$mydir/overrides"
export OVERRIDE="$OVR_DIR/$GAME.opt"

. "$mydir/default.opt"
. "$mydir/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

/mnt/SDCARD/App/utils/utils $GOV $CORES $CPU $GPU $DDR $SWAP

cd $mydir
ffplay -vf transpose=2 -fs -i "$1"
