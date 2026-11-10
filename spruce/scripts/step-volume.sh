#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

case "$1" in
    up|down)
        ;;
    *)
        echo "Usage: $0 {up|down}" >&2
        exit 2
        ;;
esac

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

# One step, as the volume keys take it; set_volume saves it to the system json PyUI watches.
case "$1" in
    up) volume_up ;;
    down) volume_down ;;
esac
