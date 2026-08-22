#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

PLAYER="/usr/trimui/apps/player/launch.sh"

if [ ! -f "$PLAYER" ]; then
    log_message "TrimUI Video Player not found at $PLAYER"
    exit 1
fi

export LD_LIBRARY_PATH="/usr/trimui/lib:${LD_LIBRARY_PATH}"
chmod +x "$PLAYER"
cd "$(dirname "$PLAYER")" || exit 1
exec "$PLAYER"
