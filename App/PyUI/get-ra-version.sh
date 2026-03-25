#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

"/mnt/SDCARD/RetroArch/$RA_BIN" --version 2>/dev/null \
| sed -n 's/^Version: \([0-9.]*\) (Git \([a-f0-9]*\)).*/\1 (\2)/p'