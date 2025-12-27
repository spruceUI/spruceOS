#!/bin/bash

# Check if the argument was passed
if [ -z "$1" ]; then
  echo "Usage: $0 <screenshot_location>"
  exit 1
fi

export LD_LIBRARY_PATH=/mnt/SDCARD/spruce/flip/lib:/usr/lib:/lib/:/mnt/SDCARD/spruce/flip/arm64-ffmpeg/bin

screenshot_location="$1"

/mnt/SDCARD/spruce/flip/arm64-ffmpeg/bin/ffmpeg \
  -f kmsgrab \
  -device /dev/dri/card0 \
  -i - \
  -vf 'hwdownload,format=bgr0' \
  -frames:v 1 \
  -y \
  "$screenshot_location"
