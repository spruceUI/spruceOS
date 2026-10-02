#!/bin/sh
# changeCmd for RetroAchievements Settings -> Share RAOfflineProxy statistics.
# PyUI appends the new value as $1. Nothing is counted or sent until this
# stores the agreement; turning it off also deletes what was counted so far.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

ra_proxy_is_installed || exit 0

if [ "$1" = "True" ]; then
	_ra_proxy_run enable-usage-stats >/dev/null 2>&1
else
	_ra_proxy_run disable-usage-stats >/dev/null 2>&1
fi

log_message "RAOfflineProxy usage statistics: $(_ra_proxy_run usage-stats-status 2>/dev/null | tail -n 1)"
