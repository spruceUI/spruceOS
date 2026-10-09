#!/bin/sh
# Usage: raproxyCacheRom.sh <rom path>

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

ROM="$1"
[ -f "$ROM" ] || { echo "No such ROM"; exit 1; }

if [ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" != "True" ]; then
	echo "RAOfflineProxy is off"
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
QUEUED="$(printf '%s' "$MSG" | jq -r '.queued // false' 2>/dev/null)"
PARSED="$(printf '%s' "$MSG" | jq -r '.message // empty' 2>/dev/null)"
[ -n "$PARSED" ] && MSG="$PARSED"

log_message "RAOfflineProxy cache-rom: $(basename "$ROM") -> $MSG"

echo "$MSG"
[ "$QUEUED" = "true" ] && exit 2
exit $RC
