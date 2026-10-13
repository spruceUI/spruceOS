#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

case "$1" in
    ''|*[!0-9]*)
        echo "Usage: $0 <level 0-20>" >&2
        exit 2
        ;;
esac

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

if ! command -v apply_volume >/dev/null 2>&1; then
    echo "Error: function 'apply_volume' is not available" >&2
    exit 1
fi

apply_volume "$1"
