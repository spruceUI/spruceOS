#!/bin/sh
# CHAI retrofit setup: NextUI
#
# Usage: setup.sh setup|teardown
#
# keymon owns the volume keys and nothing announces a change, so vol_listener
# (vol_listener.c, built static for aarch64) watches the keys and
# /dev/shm/SharedSettings and runs "chai notify-volume" on every press,
# including presses at the min/max.
#
# Rebuild: aarch64-linux-gnu-gcc -O2 -static -s -o vol_listener vol_listener.c

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

NEXTUI_LISTENER_PID="$CHAI_RUN_DIR/nextui-vol-listener.pid"

chai_setup() {
	[ -f "$NEXTUI_LISTENER_PID" ] && kill -0 "$(cat "$NEXTUI_LISTENER_PID")" 2>/dev/null && return 0
	mkdir -p "$CHAI_RUN_DIR"
	"$CHAI_RETRO_DIR/NextUI/vol_listener" "$CHAI_CMD" </dev/null >/dev/null 2>&1 &
	echo $! >"$NEXTUI_LISTENER_PID"
}

chai_teardown() {
	[ -f "$NEXTUI_LISTENER_PID" ] && kill "$(cat "$NEXTUI_LISTENER_PID")" 2>/dev/null
	rm -f "$NEXTUI_LISTENER_PID"
}

chai_setup_main "$@"
