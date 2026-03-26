#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# accommodate both relative and absolute paths for PPSSPP bin location
case "$PSP_BIN" in
    "/"*) PPSSPPSDL="$PSP_BIN" ;;
    *)    PPSSPPSDL="/mnt/SDCARD/Emu/PSP/$PSP_BIN" ;;
esac

"$PPSSPPSDL" --version 2>/dev/null