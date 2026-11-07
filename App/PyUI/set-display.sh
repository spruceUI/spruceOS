#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

case "$1" in
    contrast|saturation|brightness|hue)
        ;;
    *)
        echo "Usage: $0 {contrast|saturation|brightness|hue} <level>" >&2
        exit 2
        ;;
esac

case "$2" in
    ''|*[!0-9]*)
        echo "Usage: $0 $1 <level>" >&2
        exit 2
        ;;
esac

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

FUNCTION="apply_display_$1"
if ! command -v "$FUNCTION" >/dev/null 2>&1; then
    echo "Error: function '$FUNCTION' is not available" >&2
    exit 1
fi

"$FUNCTION" "$2"
