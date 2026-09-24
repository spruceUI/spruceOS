#!/bin/sh
# Usage: raproxyCacheRom.sh <rom path>

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

ROM="$1"
[ -f "$ROM" ] || { echo "No such ROM"; exit 1; }

if [ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" != "True" ]; then
	echo "Offline Achievements is off"
	exit 1
fi

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

MSG="$(printf '%s\n' "$OUT" | tail -n 1)"
PARSED="$(printf '%s' "$MSG" | jq -r '.message // empty' 2>/dev/null)"
[ -n "$PARSED" ] && MSG="$PARSED"

log_message "RAOfflineProxy cache-rom: $(basename "$ROM") -> $MSG"

GAME_ID=""
if [ "$RC" = "0" ]; then
	GAME_ID="$(raproxy_cached_games | awk -v title="${MSG#Cached }" '
		{
			line = $0
			sub(/ ##GAMEID:[0-9]+$/, "", line)
			sub(/ \([0-9]+ unlocks\)$/, "", line)
			if (line == title) { sub(/.*##GAMEID:/, ""); print; exit }
		}')"
fi

jq -nc --arg m "$MSG" --argjson id "${GAME_ID:-null}" '{message:$m,game_id:$id}'
exit $RC
