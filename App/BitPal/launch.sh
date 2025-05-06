#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
	BIN_DIR=/mnt/SDCARD/spruce/bin
else
	BIN_DIR=/mnt/SDCARD/spruce/bin64
fi

set_random_good_mood
FACE="$(get_face)"
display -d 2 -t "$FACE" -s 80 -p 50

GREETING="$(get_random_greeting)"
display --okay -t "$GREETING" -s 36 -p 50
sleep 0.1

FACT="$(get_random_fact)"

display --okay -t "$FACT" -s 36 -p 50
sleep 0.1

# cd "$BIN_DIR"
# do the stuff

set_random_negative_mood
GUILT_TRIP="$(get_random_guilt_trip)"
display --okay -t "$GUILT_TRIP" -s 36 -p 50
sleep 0.1