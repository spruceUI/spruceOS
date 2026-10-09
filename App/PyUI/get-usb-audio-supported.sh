#!/bin/sh

# Support cannot change within a boot, and /tmp clears at boot, so the answer is
# kept there: later menu starts skip loading the helpers.
CACHE=/tmp/usb_audio_supported
if [ -f "$CACHE" ]; then
    read -r supported < "$CACHE"
    exit "${supported:-1}"
fi

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

# PyUI reads the exit status: 0 where the device routes audio to USB sound cards.
device_usb_audio_supported
supported=$?
echo "$supported" > "$CACHE"
exit "$supported"
