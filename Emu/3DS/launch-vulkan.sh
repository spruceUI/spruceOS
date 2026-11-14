#!/bin/sh
# Keep spruce's normal CPU, zram, input, audio and return-to-menu handling.
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
if [ "$PLATFORM" = "Flip" ]; then
    export RA_BIN_64="../Emu/3DS/ra64-vulkan"
fi
. /mnt/SDCARD/spruce/scripts/emu/standard_launch.sh "$@"
