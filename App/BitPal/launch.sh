#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh

FACE="$(get_face)"
GREETING="$(get_random_greeting)"
FACT="$(get_random_fact)"

display -d 2 -t "$FACE" -s 80 -p 50

display --okay -t "$GREETING" -s 36 -p 50
sleep 0.1

display --okay -t "$FACT" -s 36 -p 50
sleep 0.1