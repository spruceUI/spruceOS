#!/bin/sh
# Usage: raproxyRemoveCached.sh <game id>

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

GAME_ID="$1"
case "$GAME_ID" in
	''|*[!0-9]*) echo "No game id"; exit 1 ;;
esac

OUT="$(raproxy_remove_cached_game "$GAME_ID")"
RC=$?
log_message "RAOfflineProxy remove-cached-game $GAME_ID -> $OUT"
printf '%s\n' "$OUT" | tail -n 1
exit $RC
