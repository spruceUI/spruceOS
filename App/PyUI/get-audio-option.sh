#!/bin/sh

case "$1" in
    defer-startup)
        FUNCTION="device_defer_startup_audio"
        ;;
    idle-release)
        FUNCTION="device_idle_release_audio"
        ;;
    *)
        echo "Usage: $0 {defer-startup|idle-release}" >&2
        exit 2
        ;;
esac

# The answer cannot change within a boot, and /tmp clears at boot, so it is kept
# there: later menu starts skip loading the helpers.
CACHE="/tmp/pyui_audio_option_$1"
if [ -f "$CACHE" ]; then
    read -r answer < "$CACHE"
    exit "${answer:-1}"
fi

HELPER_FUNCTIONS="/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

if [ ! -f "$HELPER_FUNCTIONS" ]; then
    echo "Error: helperFunctions.sh not found: $HELPER_FUNCTIONS" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$HELPER_FUNCTIONS"

# PyUI reads the exit status: 0 turns the option on for this device.
"$FUNCTION"
answer=$?
echo "$answer" > "$CACHE"
exit "$answer"
