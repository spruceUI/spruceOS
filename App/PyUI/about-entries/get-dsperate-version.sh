#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

EMU_DIR="/mnt/SDCARD/Emu/NDS"

# Same binary and libraries dsperate_functions.sh launches with
if [ "$PLATFORM" = "A30" ]; then
    DSPERATE="$EMU_DIR/dsperate.a30"
    export LD_LIBRARY_PATH="$EMU_DIR/lib:$LD_LIBRARY_PATH"
else
    DSPERATE="$EMU_DIR/dsperate"
    export LD_LIBRARY_PATH="$EMU_DIR/lib64:$LD_LIBRARY_PATH"
    [ "$PLATFORM" = "Flip" ] && export LD_LIBRARY_PATH="$EMU_DIR/DSperate_flip_lib:$LD_LIBRARY_PATH"
fi

"$DSPERATE" --version 2>/dev/null \
| sed -n 's/^DSperate v\{0,1\}\([^ ]*\) (\([^)-]*\).*)$/\1 (\2)/p'
