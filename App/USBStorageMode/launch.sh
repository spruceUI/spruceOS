#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

HERE="$(dirname "$0")"
cd "$HERE"

case "$PLATFORM" in
    "A30" ) ./launch_A30.sh ;;
    "Brick" ) ./launch_Brick.sh ;;
    "SmartPro" ) exit 20 ;;
    "Flip" ) ./launch_Flip.sh ;;
esac
