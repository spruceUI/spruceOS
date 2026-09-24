#!/bin/sh
# Cache one ROM for offline achievements, for PyUI's game options menu.
# Usage: raproxyCacheRom.sh <rom path>

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

ROM="$1"
[ -f "$ROM" ] || { echo "No such ROM"; exit 1; }

if [ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" != "True" ]; then
	echo "Offline Achievements is off"
	exit 1
fi

# Caching talks to the proxy, not straight to the network.
if ! ra_proxy_is_running; then
	start_raproxy_process
	_waited=0
	while ! ra_proxy_is_running; do
		_waited=$((_waited + 1))
		[ "$_waited" -gt 30 ] && { echo "Proxy did not start"; exit 1; }
		sleep 1
	done
fi

OUT="$(raproxy_cache_rom "$ROM")"
RC=$?

# Last line only: the JSON is printed last and anything on stderr comes first.
# .message carries the app's own wording - the 100-game cap, a missing login.
MSG="$(printf '%s\n' "$OUT" | tail -n 1)"
PARSED="$(printf '%s' "$MSG" | jq -r '.message // empty' 2>/dev/null)"
[ -n "$PARSED" ] && MSG="$PARSED"

log_message "RAOfflineProxy cache-rom: $(basename "$ROM") -> $MSG"

# The id the ROM resolved to, so the caller can drop it again later. cache-rom
# does not report it, but cached-games tags every entry with ##GAMEID:.
GAME_ID=""
if [ "$RC" = "0" ]; then
	TITLE="${MSG#Cached }"
	GAME_ID="$(raproxy_cached_games | grep -F "$TITLE ##GAMEID:" | sed -n 's/.*##GAMEID:\([0-9]*\).*/\1/p' | head -n 1)"
	[ -n "$GAME_ID" ] || GAME_ID="$(raproxy_cached_games | grep -F "$TITLE " | sed -n 's/.*##GAMEID:\([0-9]*\).*/\1/p' | head -n 1)"
fi

printf '{"message":"%s","game_id":%s}\n' "$MSG" "${GAME_ID:-null}"
exit $RC
