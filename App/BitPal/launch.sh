#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh

if [ "$PLATFORM" = "A30" ]; then
	BIN_DIR=/mnt/SDCARD/spruce/bin
else
	BIN_DIR=/mnt/SDCARD/spruce/bin64
fi

FACE="$(get_face)"
GREETING="$(get_random_greeting)"
FACT="$(get_random_fact)"
GUILT_TRIP="$(get_random_guilt_trip)"

display -d 2 -t "$FACE" -s 80 -p 50

display --okay -t "$GREETING" -s 36 -p 50
sleep 0.1

display --okay -t "$FACT" -s 36 -p 50
sleep 0.1

# cd "$BIN_DIR"
# do the stuff

export mood=sad
display --okay -t "$GUILT_TRIP" -s 36 -p 50
sleep 0.1