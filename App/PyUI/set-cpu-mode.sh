#!/bin/sh

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

case "$1" in
    smart)
        FUNCTION="set_smart"
        ;;
    powersave)
        FUNCTION="set_powersave"
        ;;
    *)
        echo "Usage: $0 {smart|powersave}" >&2
        exit 2
        ;;
esac

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

if ! command -v "$FUNCTION" >/dev/null 2>&1; then
    echo "Error: function '$FUNCTION' is not available" >&2
    exit 1
fi

"$FUNCTION"
