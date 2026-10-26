#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

"/mnt/SDCARD/RetroArch/$RA_BIN" --version 2>/dev/null \
| awk 'NR==2 {if ($3 ~ /Git/) {print $2 " (" $4} else {print $2}}'