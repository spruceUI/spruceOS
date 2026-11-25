#!/bin/sh
# CHAI retrofit setup: Knulli
#
# Usage: setup.sh setup|teardown
#
# Wraps <prefix>-audio (knulli-audio on Scarab, batocera-audio before) so
# every setSystemVolume call also runs "chai notify-volume". The volume
# buttons, ES and idle/lid mute all go through setSystemVolume. Fires even
# when already at max/min.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/setup.sh"

if [ -f /usr/share/knulli/knulli.version ]; then
	KNULLI_AUDIO=/usr/bin/knulli-audio
else
	KNULLI_AUDIO=/usr/bin/batocera-audio
fi

KNULLI_AUDIO_DIR="$CHAI_RUN_DIR/knulli-audio"

chai_setup() {
	# Avoid double mount. Checked before backing up, otherwise we'd copy our
	# own wrapper as the "original"
	findmnt -n "$KNULLI_AUDIO" >/dev/null 2>&1 && return 0

	mkdir -p "$KNULLI_AUDIO_DIR"
	cp "$KNULLI_AUDIO" "$KNULLI_AUDIO_DIR/original"
	chmod +x "$KNULLI_AUDIO_DIR/original"

	cat >"$KNULLI_AUDIO_DIR/wrapper" <<EOF
#!/bin/sh
"$KNULLI_AUDIO_DIR/original" "\$@"
RC=\$?
if [ "\$1" = "setSystemVolume" ]; then
	(
		VAL=\$("$KNULLI_AUDIO_DIR/original" getSystemVolume 2>/dev/null | tr -d '\n\r')
		[ -n "\$VAL" ] && "$CHAI_CMD" notify-volume "\$VAL" 100
	) </dev/null >/dev/null 2>&1 &
fi
exit \$RC
EOF
	chmod +x "$KNULLI_AUDIO_DIR/wrapper"
	mount --bind "$KNULLI_AUDIO_DIR/wrapper" "$KNULLI_AUDIO"
}

chai_teardown() {
	findmnt -n "$KNULLI_AUDIO" >/dev/null 2>&1 && umount -l "$KNULLI_AUDIO"
	rm -rf "$KNULLI_AUDIO_DIR"
}

chai_setup_main "$@"
