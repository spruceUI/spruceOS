#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

HELPER_MESSAGE="Will apply on next boot"

case "$1" in
    "1")
        echo -n "Requires at least one game in GS"
        return 0
        ;;
    "2")
        echo -n "Requires pico8.dat and pico8_dyn in Pico-8 bin folder"
        return 0
        ;;
    *)
        echo -n "$HELPER_MESSAGE"
        return 0
        ;;
esac