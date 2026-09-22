#! /bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# RAOfflineProxy: a local proxy that stands in for retroachievements.org so
# achievements can be earned offline and flushed when the network returns.
# https://github.com/misantronic/RAOfflineProxy
#
# The app ships as a normal App. spruce owns only when it runs and where
# RetroArch points (see prepare_ra_config in emu/lib/ra_functions.sh); the app
# owns its own runtime, its menu and its cache.
RA_PROXY_DIR=/mnt/SDCARD/App/RAOfflineProxy
RA_PROXY_BOOT="$RA_PROXY_DIR/autostart-launch.sh"

# The daemon runs as "python -m raofflineproxy.boot". Matched on the module
# rather than the app directory so the menu, which is raofflineproxy.main out
# of the same tree, is never caught by a stop.
RA_PROXY_PROC="raofflineproxy.boot"

ra_proxy_is_installed() {
	[ -f "$RA_PROXY_BOOT" ]
}

ra_proxy_is_running() {
	pgrep -f "$RA_PROXY_PROC" >/dev/null 2>&1
}

start_raproxy_process() {
	if ! ra_proxy_is_installed; then
		log_message "RAOfflineProxy: enabled but not installed at $RA_PROXY_DIR"
		return 1
	fi

	# Its own launcher resolves the bundled interpreter and environment, which
	# differ per device. Reimplementing that here would drift the moment the
	# app changes.
	sh "$RA_PROXY_BOOT" &
}

stop_raproxy_process() {
	pkill -f "$RA_PROXY_PROC" 2>/dev/null
}
