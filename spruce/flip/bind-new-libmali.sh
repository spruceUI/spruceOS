#!/bin/sh

# Bind over the system's copy, but only where the system has one: a bind needs an
# existing target, and BaseOS-my355 does not ship every one of these names.
SKIPPED=""
bind_lib() {
	if [ -e "$2" ]; then
		mount --bind "$1" "$2"
	else
		SKIPPED="$SKIPPED ${2##*/}"
	fi
}

bind_lib /mnt/SDCARD/spruce/flip/libmali-bifrost-g52-g2p0-gbm.so /lib/libmali.so
bind_lib /mnt/SDCARD/spruce/flip/libmali-bifrost-g52-g2p0-gbm.so /lib/libmali.so.1
bind_lib /mnt/SDCARD/spruce/flip/libmali-bifrost-g52-g2p0-gbm.so /lib/libmali.so.1.9.0

if [ -n "$SKIPPED" ]; then
	echo "bind-new-libmali: not on this system, skipped:$SKIPPED"
fi
