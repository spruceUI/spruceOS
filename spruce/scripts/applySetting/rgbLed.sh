#!/bin/sh
# changeCmd for the RGB LED settings: apply on change instead of waiting for the
# next return to the menu. Backgrounded - PyUI runs changeCmd on the UI thread.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

(
    enable_or_disable_rgb
    set_rgb_in_menu
) </dev/null >/dev/null 2>&1 &
