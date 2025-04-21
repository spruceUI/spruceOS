#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

HELPER_MESSAGE="Will apply on next boot"

case "$1" in
    "1")
        echo -n "Boot straight into a random game"
        exit 0
        ;;
    "2")
        echo -n "Requires at least one game in GS"
        exit 0
        ;;
    "3")
        echo -n "Requires Pico-8 binaries"
        exit 0
        ;;
    *)
        echo -n "$HELPER_MESSAGE"
        exit 0
        ;;
esac
