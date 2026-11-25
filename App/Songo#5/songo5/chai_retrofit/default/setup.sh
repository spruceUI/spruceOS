#!/bin/sh
# CHAI retrofit: default setup
#
# Usage: setup.sh setup|teardown
#
# Wraps wpctl and pactl so any call that changes the default sink's volume
# or mute also runs "chai notify-volume". CFW profiles source this file with
# CHAI_PROFILE_SOURCED=1, override chai_setup/chai_teardown, and can still
# call the PipeWire functions below.

CHAI_RETRO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHAI_RUN_DIR="/tmp/chai_retrofit"

# The chai.sh next to the setup.sh being run, so wrappers call that profile's chai
CHAI_CMD="$(cd "$(dirname "$0")" && pwd)/chai.sh"

CHAI_PW_DIR="$CHAI_RUN_DIR/pipewire"

chai_setup_pipewire() {
	mkdir -p "$CHAI_PW_DIR"
	sed "s#__CHAI__#$CHAI_CMD#; s#__DIR__#$CHAI_PW_DIR#" \
		"$CHAI_RETRO_DIR/default/vol_wrapper" >"$CHAI_PW_DIR/vol_wrapper"
	chmod +x "$CHAI_PW_DIR/vol_wrapper"

	for NAME in wpctl pactl; do
		BIN=$(command -v "$NAME" 2>/dev/null) || continue
		BIN=$(readlink -f "$BIN")
		# Check the mount before copying, otherwise we'd back up our own wrapper
		grep -q " $BIN " /proc/mounts && continue
		cp "$BIN" "$CHAI_PW_DIR/$NAME.orig"
		chmod +x "$CHAI_PW_DIR/$NAME.orig"
		mount --bind "$CHAI_PW_DIR/vol_wrapper" "$BIN" && echo "$BIN" >>"$CHAI_PW_DIR/mounted"
	done
}

chai_teardown_pipewire() {
	if [ -f "$CHAI_PW_DIR/mounted" ]; then
		while read -r BIN; do
			umount -l "$BIN"
		done <"$CHAI_PW_DIR/mounted"
	fi
	rm -rf "$CHAI_PW_DIR"
}

chai_setup() {
	chai_setup_pipewire
}

chai_teardown() {
	chai_teardown_pipewire
}

chai_setup_main() {
	case "$1" in
		setup) chai_setup ;;
		teardown) chai_teardown ;;
		*)
			echo "usage: $0 setup|teardown" >&2
			exit 1
			;;
	esac
}

[ -n "$CHAI_PROFILE_SOURCED" ] || chai_setup_main "$@"
