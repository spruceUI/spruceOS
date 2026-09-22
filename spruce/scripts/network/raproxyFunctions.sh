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
RA_PROXY_COMMON="$RA_PROXY_DIR/common.sh"

# raofflineproxy.boot is only a bootstrap; it forks the real daemon and exits,
# so matching .boot finds nothing a moment later - the toggle then reported the
# proxy as stopped while it was serving, and could neither stop nor avoid
# restarting it. The service and the menu are both raofflineproxy.main, so the
# verb is what separates them and menu-sdl has to survive a stop.
#
# No leading dash either: pgrep reads one as an option and fails outright.
RA_PROXY_PROC="raofflineproxy\.main run-service"

ra_proxy_is_installed() {
	[ -f "$RA_PROXY_COMMON" ]
}

ra_proxy_is_running() {
	pgrep -f "$RA_PROXY_PROC" >/dev/null 2>&1
}

start_raproxy_process() {
	if ! ra_proxy_is_installed; then
		log_message "RAOfflineProxy: enabled but not installed at $RA_PROXY_DIR"
		return 1
	fi

	# start-proxy, not the app's autostart-launch.sh: that runs boot-reconcile,
	# which honours the app's *own* autostart flag and quietly does nothing when
	# it is off. Enabling lives in our toggle now, and two switches for one
	# feature is how a user ends up with a setting that says On and nothing
	# running - which is exactly what it did.
	#
	# Sourcing the app's common.sh rather than reimplementing it: resolving the
	# interpreter and its environment differs per device and is the app's to
	# own. In a subshell so none of it leaks into the caller.
	(
		cd "$RA_PROXY_DIR" || exit 1
		. "$RA_PROXY_COMMON"
		prepare_env
		resolve_python_bin || exit 1
		run_backend_raw "$RESOLVED_PYTHON_BIN" start-proxy
	) >/dev/null 2>&1 &
}

# stop-proxy, not a kill: the app restores the RetroArch host it saved when it
# patched, and a user's own custom host is part of that. Killing the process
# leaves cheevos_custom_host pointing at a port with nothing behind it, and
# RetroArch then fails to reach achievements with nothing on screen to say why.
# pkill stays only for a process that ignored the request.
stop_raproxy_process() {
	if [ -f "$RA_PROXY_COMMON" ]; then
		(
			cd "$RA_PROXY_DIR" || exit 1
			. "$RA_PROXY_COMMON"
			prepare_env
			resolve_python_bin || exit 1
			run_backend_raw "$RESOLVED_PYTHON_BIN" stop-proxy
		) >/dev/null 2>&1
	fi

	ra_proxy_is_running || return 0
	log_message "RAOfflineProxy: stop-proxy left it running, killing"
	pkill -f "$RA_PROXY_PROC" 2>/dev/null
}

# Cache one ROM's achievement set for offline play, and print whatever the app
# says - the 100-game cap and "not logged in" both come back this way, and the
# caller shows it to the user verbatim.
#
# Needs the network: this is the call that fetches from retroachievements.org
# so the game can be played without it later.
raproxy_cache_rom() {
	_rom="$1"

	if ! ra_proxy_is_installed; then
		echo "RAOfflineProxy is not installed"
		return 1
	fi

	(
		cd "$RA_PROXY_DIR" || exit 1
		. "$RA_PROXY_COMMON"
		prepare_env
		resolve_python_bin || { echo "No usable python"; exit 1; }
		run_backend_raw "$RESOLVED_PYTHON_BIN" cache-rom --path "$_rom" 2>&1
	)
}
