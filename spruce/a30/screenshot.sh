#!/bin/sh

/mnt/SDCARD/spruce/bin/fbgrab -a -f "/dev/fb0" -w "480" -h "640" -b 32 -l "480" "/tmp/screenshot.png" 2>/dev/null 

rm "$1"

/mnt/SDCARD/spruce/bin/ffmpeg -i "/tmp/screenshot.png" -vf "transpose=1" "$1"
