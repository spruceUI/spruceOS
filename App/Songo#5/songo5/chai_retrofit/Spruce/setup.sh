#!/bin/sh
# CHAI retrofit setup: Spruce
#
# Usage: setup.sh setup|teardown
#
# Starts vol_listener, which watches the volume keys and runs
# "chai notify-volume" with Spruce's volume after each press.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

VOL_LISTENER="$CHAI_RETRO_DIR/Spruce/vol_listener"

chai_setup() {
	# Clear out any listener a crashed or older launch left running, so there's
	# only ever one
	chai_teardown
	sh "$VOL_LISTENER" "$CHAI_CMD" </dev/null >/dev/null 2>&1 &
}

# Finds this install's listeners by their full command line in /proc. busybox's
# ps cuts the command line off at the terminal width, which used to leave the
# "chai_retrofit/Spruce/vol_listener" part out of view, so nothing matched and
# every launch leaked a listener.
_vol_listener_pids() {
	# One grep for every process: a fork for each took over a second on a Brick.
	# The pattern goes in on stdin so grep's own command line doesn't match.
	printf '%s\n' "$VOL_LISTENER" | grep -lF -f - /proc/[0-9]*/cmdline 2>/dev/null |
		while IFS=/ read -r _ _ PID _; do echo "$PID"; done
}

# Kills the given processes and everything under them. A listener is a pipeline
# (inotifywait or getevent feeding a while loop in a subshell), and
# inotifywait/getevent don't carry the listener's path in their command line,
# so they're found through their parent instead. The whole tree is collected
# before anything is killed: a child whose parent dies first is moved under
# init and can't be traced back any more.
_kill_tree() { # <pid>...
	[ -n "$*" ] || return 0
	PIDS="$(
		for STAT in /proc/[0-9]*/stat; do
			read -r LINE <"$STAT" 2>/dev/null || continue
			PID="${STAT#/proc/}"
			# Drop "pid (comm) " (comm can hold spaces), leaving "state ppid ..."
			LINE="${LINE##*") "}"
			echo "${PID%/stat} ${LINE#* }"
		done | awk -v roots="$*" '
			{ parent[$1] = $2 }
			END {
				n = split(roots, list, " ")
				for (i = 1; i <= n; i++) tree[list[i]] = 1
				added = 1
				while (added) {
					added = 0
					for (p in parent)
						if (!(p in tree) && (parent[p] in tree)) { tree[p] = 1; added = 1 }
				}
				for (p in tree) printf "%s ", p
			}'
	)"
	# shellcheck disable=SC2086
	[ -n "$PIDS" ] && kill $PIDS 2>/dev/null
	return 0
}

chai_teardown() {
	# shellcheck disable=SC2046
	_kill_tree $(_vol_listener_pids)
}

chai_setup_main "$@"
