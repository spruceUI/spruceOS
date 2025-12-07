#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

HERE="$(dirname "$0")"
cd "$HERE"

case "$PLATFORM" in
    "SmartPro" ) exit 20 ;;
    * ) ./launch_${PLATFORM}.sh ;;
esac
