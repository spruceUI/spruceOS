#!/bin/sh
# CHAI retrofit setup: TrimUI stock firmware and CrossMix
#
# Usage: setup.sh setup|teardown
#
# Starts vol_listener, which watches the volume level TrimUI's firmware
# writes and runs "chai notify-volume" when it changes.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

TRIMUI_LISTENER_PID="$CHAI_RUN_DIR/trimui-vol-listener.pid"

chai_setup() {
	[ -f "$TRIMUI_LISTENER_PID" ] && kill -0 "$(cat "$TRIMUI_LISTENER_PID")" 2>/dev/null && return 0
	mkdir -p "$CHAI_RUN_DIR"
	sh "$CHAI_RETRO_DIR/TrimUI/vol_listener" "$CHAI_CMD" </dev/null >/dev/null 2>&1 &
	echo $! >"$TRIMUI_LISTENER_PID"
}

# The listener traps TERM and kills its own child (inotifywait or sleep), so
# killing its pid is enough
chai_teardown() {
	[ -f "$TRIMUI_LISTENER_PID" ] && kill "$(cat "$TRIMUI_LISTENER_PID")" 2>/dev/null
	rm -f "$TRIMUI_LISTENER_PID"
}

chai_setup_main "$@"
