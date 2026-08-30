#!/bin/bash

# Check if the argument was passed
if [ -z "$1" ]; then
  echo "Usage: $0 <screenshot_location>"
  exit 1
fi

export LD_LIBRARY_PATH=/mnt/SDCARD/spruce/flip/lib:/usr/lib:/lib/:/mnt/SDCARD/spruce/flip/arm64-ffmpeg/bin

screenshot_location="$1"

# bgra, not bgr0. kmsgrab hands hwdownload whatever DRM format the plane
# actually uses, and this panel's is ARGB8888 - bgr0 is XRGB8888, so hwdownload
# rejected it with "Invalid output format bgr0 for hwframe download" and ffmpeg
# wrote nothing. The grab itself was always fine; only the download failed, so
# the shortcut rumbled and produced no file. Checked on hardware: of bgra, rgba,
# argb, abgr, rgb0 and 0rgb, bgra is the only one hwdownload accepts here.

/mnt/SDCARD/spruce/flip/arm64-ffmpeg/bin/ffmpeg \
  -f kmsgrab \
  -device /dev/dri/card0 \
  -i - \
  -vf 'hwdownload,format=bgra' \
  -frames:v 1 \
  -y \
  "$screenshot_location"
