#!/bin/sh
# Cycle the LCD backlight through a few levels on each Fn key press.
# Uses spruce's own set_backlight so the hardware, the stored value, and the
# in-UI brightness slider all stay in sync (the stock /tmp/system/set_brightness
# path is not honored under spruce and desyncs the slider).

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

CURRENT=$(current_backlight)
echo "get brightness:$CURRENT"

# Cycle 1 -> 4 -> 7 -> 10 -> 1 (spruce clamps to 1..10)
if [ "$CURRENT" -lt 4 ]; then
    NEXT=4
elif [ "$CURRENT" -lt 7 ]; then
    NEXT=7
elif [ "$CURRENT" -lt 10 ]; then
    NEXT=10
else
    NEXT=1
fi

echo "set brightness:$NEXT"
set_backlight "$NEXT"
