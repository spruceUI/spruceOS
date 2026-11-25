#!/bin/sh
# CHAI retrofit setup: ArkOS family (ArkOS, dArkOS)
#
# Usage: setup.sh setup|teardown
#
# There's no PipeWire here. The volume keys belong to ogage, which runs
# "amixer -q sset Playback 1%+/-" (or dArkOS's volume.sh, which runs
# "amixer -q sset Master ..."). amixer_wrapper is bind-mounted over amixer so
# each of those calls also runs "chai notify-volume". It fires even when the
# volume is already at the min/max.
#
# Ports run as the ark user, which has passwordless sudo, so anything that
# needs root goes through "sudo -n".

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

ARK_AMIXER_DIR="$CHAI_RUN_DIR/amixer"

# Runs a command as root: directly if already root, otherwise with sudo -n
chai_ark_root() {
	if [ "$(id -u)" = 0 ]; then
		"$@"
	else
		sudo -n "$@"
	fi
}

chai_setup() {
	AMIXER=$(command -v amixer 2>/dev/null) || return 0
	AMIXER=$(readlink -f "$AMIXER")
	# Avoid a double mount. Checked before backing up, otherwise we'd copy our
	# own wrapper as the "original"
	grep -q " $AMIXER " /proc/mounts && return 0

	mkdir -p "$ARK_AMIXER_DIR"
	cp "$AMIXER" "$ARK_AMIXER_DIR/amixer.orig" || return 0
	chmod +x "$ARK_AMIXER_DIR/amixer.orig"
	sed "s#__CHAI__#$CHAI_CMD#; s#__DIR__#$ARK_AMIXER_DIR#" \
		"$CHAI_RETRO_DIR/ArkOS/amixer_wrapper" >"$ARK_AMIXER_DIR/amixer_wrapper"
	chmod +x "$ARK_AMIXER_DIR/amixer_wrapper"

	chai_ark_root mount --bind "$ARK_AMIXER_DIR/amixer_wrapper" "$AMIXER" &&
		echo "$AMIXER" >"$ARK_AMIXER_DIR/mounted"
}

chai_teardown() {
	if [ -f "$ARK_AMIXER_DIR/mounted" ]; then
		while read -r BIN; do
			chai_ark_root umount -l "$BIN"
		done <"$ARK_AMIXER_DIR/mounted"
	fi
	rm -rf "$ARK_AMIXER_DIR"
}

chai_setup_main "$@"
