#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

if ! command -v bt_audio_device >/dev/null 2>&1; then
    echo "Error: function 'bt_audio_device' is not available" >&2
    exit 1
fi

# PyUI reads the last line: the device, or empty for the default output.
echo "$(bt_audio_device)"
