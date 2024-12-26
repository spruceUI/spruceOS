#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

HELPER_MESSAGE="Will apply on next boot"

case "$1" in
    "1")
        echo -n "Requires at least one game in GS"
        return 0
        ;;
    "2")
        echo -n "Requires Pico-8 binaries"
        return 0
        ;;
    *)
        echo -n "$HELPER_MESSAGE"
        return 0
        ;;
esac