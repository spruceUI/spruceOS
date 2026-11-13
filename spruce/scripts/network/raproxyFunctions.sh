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
	(
		_out="$(_ra_proxy_run start-proxy 2>&1)" && exit 0
		log_message "RAOfflineProxy: start-proxy failed: $_out"
		ra_proxy_unpatch_host
	) &
}

# A broken install cannot restore the host it patched in, which leaves
# RetroArch logging in to nothing.
ra_proxy_unpatch_host() {
	sed -i 's|^cheevos_custom_host = "127\.0\.0\.1:[0-9]*"$|cheevos_custom_host = ""|' "$(ensure_ra_config_path)"
}

# Not a kill: the app restores the RetroArch host it replaced, and a user's own
# custom host is part of that.
stop_raproxy_process() {
	if ! ra_proxy_is_installed || ! _out="$(_ra_proxy_run stop-proxy 2>&1)"; then
		log_message "RAOfflineProxy: stop-proxy failed: $_out"
		ra_proxy_unpatch_host
	fi

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

# Saves the RAOfflineProxy setting as off. Hardcore and the proxy don't mix: the
# proxy can't validate a hardcore run.
raproxy_setting_off() {
	_json=/mnt/SDCARD/Saves/spruce/spruce-config.json
	_tmp="$(mktemp)"
	if jq --indent 4 '.menuOptions["RetroAchievements Settings"].enableOfflineProxy.selected = "False"' "$_json" > "$_tmp"; then
		mv "$_tmp" "$_json"
	else
		rm -f "$_tmp"
		return 1
	fi
}

# host:port of the proxy when it is enabled and running, else nothing
raproxy_address() {
	[ "$(get_config_value '.menuOptions."RetroAchievements Settings".enableOfflineProxy.selected' "False")" = "True" ] || return 1
	ra_proxy_is_running || return 1
	_port="$(jq -r '.proxy_port // empty' "$RA_PROXY_DIR/data/config.json" 2>/dev/null)"
	echo "127.0.0.1:${_port:-8099}"
}

# Prints a RetroAchievements token for the account, or nothing. Through the proxy
# when it runs: with WiFi off for a game, it answers from its cached login.
# $3 is the user agent.
rac_login_token() {
	_u="$(printf '%s' "$1" | sed 's/%/%25/g; s/+/%2B/g; s/#/%23/g; s/&/%26/g; s/ /%20/g')"
	_p="$(printf '%s' "$2" | sed 's/%/%25/g; s/+/%2B/g; s/#/%23/g; s/&/%26/g; s/ /%20/g')"
	_ua="${3:-spruceOS}"
	if _addr="$(raproxy_address)"; then
		_url="http://$_addr/dorequest.php?r=login2&u=$_u&p=$_p"
	else
		_url="https://retroachievements.org/dorequest.php?r=login&u=$_u&p=$_p"
	fi
	if command -v curl >/dev/null 2>&1; then
		_resp="$(curl -sS -f --connect-timeout 15 -A "$_ua" "$_url" 2>/dev/null)"
		case "$?" in
			35|51|58|59|60|77) _resp="$(curl -k -sS -f --connect-timeout 15 -A "$_ua" "$_url" 2>/dev/null)" ;;
		esac
	else
		_resp="$(wget -q --no-check-certificate -U "$_ua" -O - "$_url" 2>/dev/null)"
	fi
	printf '%s' "$_resp" | sed -n 's/.*"Token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

raproxy_cached_games_json() {
	ra_proxy_is_installed || return 1
	_ra_proxy_run cached-games --json 2>/dev/null
}

raproxy_rom_is_cached() {
	_dir="$(dirname "$1")"
	raproxy_cached_games_json | jq -e --arg k "/${_dir##*/}/${1##*/}" 'any(.[]; .rom_path == $k)' >/dev/null 2>&1
}

raproxy_remove_cached_game() {
	ra_proxy_is_installed || { echo "RAOfflineProxy is not installed"; return 1; }
	_ra_proxy_run remove-cached-game --game-id "$1" 2>&1
}

raproxy_cli() {
	ra_proxy_is_installed || { echo "RAOfflineProxy is not installed"; return 1; }
	_ra_proxy_run "$@"
}
