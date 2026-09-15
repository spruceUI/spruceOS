#!/bin/sh
# Run from the repository root with: sh tests/time-limit.sh
set -eu
cd "$(dirname "$0")/.."
. ./spruce/scripts/network/timeFunctions.sh

# Model both timeout interfaces without changing the clock or using the network.
timeout() {
	case "$style" in
	modern) [ "$1" != -t ] || return 125 ;;
	legacy) [ "$1" = -t ] || return 127; shift ;;
	esac
	[ "$1" = 1 ] || [ "$1" = 20 ] || return 125
	shift
	"$@"
}

calls=0
backend() {
	calls=$((calls + 1))
	[ "$#" = 2 ] && [ "$1" = 'argument with spaces' ] && [ "$2" = '' ] || return 99
	return 7
}

check_backend() {
	calls=0
	status=0
	run_with_time_limit 20 backend 'argument with spaces' '' || status=$?
	[ "$status" = 7 ] && [ "$calls" = 1 ] || {
		printf 'FAIL: %s (status=%s calls=%s)\n' "$style" "$status" "$calls"
		exit 1
	}
	printf 'PASS: %s preserves arguments, exit status, and single execution\n' "$style"
}

style=modern
check_backend
style=legacy
check_backend
unset -f timeout
style=missing
PATH=/nonexistent
check_backend
