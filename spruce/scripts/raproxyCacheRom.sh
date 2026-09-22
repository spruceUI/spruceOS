#!/bin/sh
# Cache one ROM for offline achievements. Called by PyUI's game options menu.
#
# Usage: raproxyCacheRom.sh <rom path>
#
# Prints a single line for the UI to show, and exits non-zero when the ROM
# could not be cached.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

ROM="$1"

if [ -z "$ROM" ] || [ ! -f "$ROM" ]; then
    echo "No such ROM"
    exit 1
fi

if [ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" != "True" ]; then
    echo "Offline Achievements is off"
    exit 1
fi

# The proxy has to be up: caching talks to it, not straight to the network.
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

# One line, last is the outcome; the UI has room for little more.
echo "$OUT" | tail -n 1
exit $RC
