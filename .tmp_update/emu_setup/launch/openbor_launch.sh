#!/bin/sh

export HOME=`dirname "$0"`
export mypak=`basename "$1"`
export OVR_DIR="$HOME/overrides"
export OVERRIDE="$OVR_DIR/$mypak.opt"

. "$HOME/default.opt"
. "$HOME/system.opt"
if [ -f "$OVERRIDE" ]; then
	. "$OVERRIDE";
fi

/mnt/SDCARD/App/utils/utils "conservative" 4 1344 384 1080 1

export LD_LIBRARY_PATH=lib:/usr/miyoo/lib:/usr/lib

cd $HOME
if [ "$mypak" == "Final Fight LNS.pak" ]; then
    ./OpenBOR_mod "$1"
else
    ./OpenBOR_new "$1"
fi
sync
