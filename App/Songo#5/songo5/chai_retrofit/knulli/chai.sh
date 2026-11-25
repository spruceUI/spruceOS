#!/bin/sh
# CHAI retrofit: Knulli
#
# Scarab onwards and older releases. Scarab renamed batocera-* tools and files
# to knulli-*. Anything not overridden here uses the default profile.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/chai.sh"

# Scarab onwards ships knulli.version, older releases only batocera.version
if [ -f /usr/share/knulli/knulli.version ]; then
	KNULLI_PREFIX=knulli
else
	KNULLI_PREFIX=batocera
fi

# <prefix>-brightness exists on every board and prints a percent.
# set-brightness stays on the default profile's direct sysfs write, which is
# fast enough for fades (knulli-brightness takes a lock on every call).
chai_get_brightness() {
	PCT=$("$KNULLI_PREFIX-brightness" 2>/dev/null)
	case "$PCT" in '' | *[!0-9]*) return 1 ;; esac
	[ "$PCT" -gt 100 ] && PCT=100
	echo $(((PCT * 255 + 50) / 100))
}

chai_get_battery_percent() {
	# Scarab: prefers batteryplus's /tmp/battery.percent, which ES shows too
	if [ "$KNULLI_PREFIX" = knulli ]; then
		chai_print_percent "$(knulli-battery-check capacity 2>/dev/null | tr -d '[:space:]')" && return 0
	fi

	# Older releases: the same detection batocera-info uses
	for D in /sys/class/power_supply/*BAT* /sys/class/power_supply/*bat*; do
		[ -d "$D" ] || continue
		chai_print_percent "$(tr -d '[:space:]' <"$D/capacity" 2>/dev/null)" && return 0
		break
	done

	# Fuel gauge devices report charge instead of capacity
	for D in /sys/class/power_supply/*FUEL* /sys/class/power_supply/*fuel*; do
		[ -d "$D" ] || continue
		NOW=$(cat "$D/charge_now" 2>/dev/null)
		FULL=$(cat "$D/charge_full" 2>/dev/null)
		case "$NOW$FULL" in '' | *[!0-9]*) break ;; esac
		[ "$FULL" -gt 0 ] && chai_print_percent $(((NOW * 100 + FULL / 2) / FULL)) && return 0
		break
	done

	chai_default_get_battery_percent
}

chai_get_battery_status() {
	if [ "$KNULLI_PREFIX" = knulli ]; then
		STATUS=$(knulli-battery-check status 2>/dev/null | head -n 1 | tr -d '\r')
		[ -n "$STATUS" ] && { chai_print_charging "$STATUS"; return 0; }
	fi

	for D in /sys/class/power_supply/*BAT* /sys/class/power_supply/*bat* /sys/class/power_supply/*FUEL* /sys/class/power_supply/*fuel*; do
		[ -d "$D" ] || continue
		STATUS=$(head -n 1 "$D/status" 2>/dev/null | tr -d '\r')
		[ -n "$STATUS" ] && { chai_print_charging "$STATUS"; return 0; }
	done

	chai_default_get_battery_status
}

# Two parts:
#  - A *.pause file in /var/run/battery-saver. idlewatcher (Scarab) and
#    battery-saver.sh (older) skip their idle action (dim, dispoff, suspend,
#    shutdown) and extended action while any exists.
#  - Hide the board's "lid" capability. lid-control and lid_shutdown exit
#    early without it, so closing the lid does nothing. A bind mount is gone
#    after a reboot, so a crash can't leave it.
KNULLI_PAUSE="/var/run/battery-saver/chai-retrofit.pause"
KNULLI_CAPABILITY="/boot/boot/$KNULLI_PREFIX.board.capability"
KNULLI_CAPABILITY_OVERRIDE="$CHAI_RUN_DIR/board.capability"

chai_set_idle_suppression() {
	case "$1" in
		1)
			mkdir -p "${KNULLI_PAUSE%/*}" "$CHAI_RUN_DIR"
			touch "$KNULLI_PAUSE"
			# Checked before copying, otherwise we'd copy our own override
			if [ -f "$KNULLI_CAPABILITY" ] && ! findmnt -n "$KNULLI_CAPABILITY" >/dev/null 2>&1; then
				sed 's/\blid\b//g' "$KNULLI_CAPABILITY" | tr -s ' ' >"$KNULLI_CAPABILITY_OVERRIDE"
				mount --bind "$KNULLI_CAPABILITY_OVERRIDE" "$KNULLI_CAPABILITY"
			fi
			;;
		0)
			rm -f "$KNULLI_PAUSE"
			findmnt -n "$KNULLI_CAPABILITY" >/dev/null 2>&1 && umount -l "$KNULLI_CAPABILITY"
			rm -f "$KNULLI_CAPABILITY_OVERRIDE"
			;;
	esac
	return 0
}

chai_get_path() {
	case "$1" in
		userdata) echo /userdata ;;
		screenshots) echo /userdata/screenshots ;;
		media) echo /userdata/music ;;
		roms) echo /userdata/roms ;;
		*) return 1 ;;
	esac
}

chai_main "$@"
