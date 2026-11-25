#!/bin/sh
# Songo's CHAI volume subscriber. Songo5.sh registers it with
# "chai add-volume-subscriber", and chai runs it on every volume change as:
#   chai_volume_subscriber.sh VOLUME MAX
# Sends the volume as a 0-100 percent to Godot's volume listener
# (utilities/volume_tcp_listener), which shows the volume overlay.

HOST="127.0.0.1"
PORT="23456"

VOL="$1"
MAX="${2:-100}"
case "$VOL" in '' | *[!0-9]*) exit 0 ;; esac
case "$MAX" in '' | *[!0-9]* | 0) MAX=100 ;; esac

PCT=$((VOL * 100 / MAX))

if command -v nc >/dev/null 2>&1; then
	echo "$PCT" | nc "$HOST" "$PORT" 2>/dev/null
elif command -v bash >/dev/null 2>&1; then
	# busybox builds without nc (eg: Spruce)
	bash -c "echo $PCT >/dev/tcp/$HOST/$PORT" 2>/dev/null
fi
