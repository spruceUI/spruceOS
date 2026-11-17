#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

if ! command -v apply_stick_calibration >/dev/null 2>&1; then
    echo "Error: function 'apply_stick_calibration' is not available" >&2
    exit 1
fi

apply_stick_calibration
