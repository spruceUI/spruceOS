#! /bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# RAOfflineProxy: a local stand-in for retroachievements.org, so achievements
# can be earned offline and flushed when the network returns.
# https://github.com/misantronic/RAOfflineProxy
RA_PROXY_DIR=/mnt/SDCARD/App/RAOfflineProxy
RA_PROXY_COMMON="$RA_PROXY_DIR/common.sh"

# raofflineproxy.boot only forks the daemon and exits, so matching it finds
# nothing. The menu shares the module, hence the verb.
RA_PROXY_PROC="raofflineproxy\.main run-service"

ra_proxy_is_installed() {
	[ -f "$RA_PROXY_COMMON" ]
}

ra_proxy_is_running() {
	pgrep -f "$RA_PROXY_PROC" >/dev/null 2>&1
}

# Sourcing the app's common.sh in a subshell: resolving its interpreter and
# environment is the app's business, and none of it should leak into ours.
_ra_proxy_run() {
	(
		cd "$RA_PROXY_DIR" || exit 1
		. "$RA_PROXY_COMMON"
		prepare_env
		resolve_python_bin || exit 1
		run_backend_raw "$RESOLVED_PYTHON_BIN" "$@"
	)
}

start_raproxy_process() {
	if ! ra_proxy_is_installed; then
		log_message "RAOfflineProxy: enabled but not installed at $RA_PROXY_DIR"
		return 1
	fi

	# start-proxy, not boot-reconcile: that one obeys the app's own autostart
	# flag and does nothing when it is off.
	_ra_proxy_run start-proxy >/dev/null 2>&1 &
}

# Not a kill: the app restores the RetroArch host it replaced, and a user's own
# custom host is part of that.
stop_raproxy_process() {
	ra_proxy_is_installed && _ra_proxy_run stop-proxy >/dev/null 2>&1

	ra_proxy_is_running || return 0
	log_message "RAOfflineProxy: stop-proxy left it running, killing"
	pkill -f "$RA_PROXY_PROC" 2>/dev/null
}

raproxy_cache_rom() {
	ra_proxy_is_installed || { echo "RAOfflineProxy is not installed"; return 1; }
	_ra_proxy_run cache-rom --path "$1" --json 2>&1
}

# Deliberately not gated on the network, unlike the services beside it: this is
# the one whose whole job is to work without it. Turning WiFi off used to stop
# it, which is exactly when it is needed.
raproxy_apply() {
	if [ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" = "True" ]; then
		ra_proxy_is_running || start_raproxy_process
	else
		stop_raproxy_process
	fi
}
