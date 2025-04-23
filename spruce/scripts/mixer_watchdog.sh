#!/bin/sh

. /mnt/SDCARD/spruce/scripts/audioFunctions.sh

count=0
# TODO: will need to fix for brick and tsp
[ "$PLATFORM" = "Flip" ] && while true; do
  set_playback_path $count
  ((count++))
done
