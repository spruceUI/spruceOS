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
log_message "RAOfflineProxy cache-rom: $(basename "$ROM") -> $OUT"
echo "$OUT" | tail -n 1
exit $RC
