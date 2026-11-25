#!/bin/sh
# CHAI retrofit: default profile
#
# Used for CFWs that don't ship chai and don't have their own retrofit profile.
# CFW profiles source this file with CHAI_PROFILE_SOURCED=1, override the
# functions they need, then call chai_main. Anything they don't override falls
# back to the functions here.

CHAI_RETRO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHAI_RUN_DIR="/tmp/chai_retrofit"
CHAI_VOL_SUBS="$CHAI_RUN_DIR/volume_subscribers"

# ---------------------------------------------------------------------------
# Brightness: sysfs backlight, or Allwinner dispdbg
# ---------------------------------------------------------------------------

# Sets BL_DIR for a sysfs backlight (scaled from max_brightness), or
# BL_DISPDBG=1 for Allwinner's dispdbg (already 0-255)
chai_bl_detect() {
	BL_DIR=
	BL_DISPDBG=0
	for D in /sys/class/backlight/*; do
		[ -f "$D/brightness" ] && { BL_DIR="$D"; return 0; }
	done
	[ -e /sys/kernel/debug/dispdbg/command ] && { BL_DISPDBG=1; return 0; }
	return 1
}

chai_bl_max() {
	M=$(cat "$BL_DIR/max_brightness" 2>/dev/null)
	case "$M" in '' | *[!0-9]* | 0) M=255 ;; esac
	echo "$M"
}

chai_default_get_brightness() {
	chai_bl_detect || return 1
	if [ -n "$BL_DIR" ]; then
		RAW=$(cat "$BL_DIR/brightness" 2>/dev/null)
		case "$RAW" in '' | *[!0-9]*) return 1 ;; esac
		MAX=$(chai_bl_max)
		VAL=$(((RAW * 255 + MAX / 2) / MAX))
		[ "$VAL" -gt 255 ] && VAL=255
		echo "$VAL"
	else
		# busybox grep has no -P
		sed -n 's/.*backlight([[:space:]]*\([0-9][0-9]*\).*/\1/p' /sys/class/disp/disp/attr/sys | head -n 1
	fi
}

chai_default_set_brightness() {
	VAL="$1"
	case "$VAL" in '' | *[!0-9]*) return 1 ;; esac
	[ "$VAL" -gt 255 ] && VAL=255
	chai_bl_detect || return 1

	if [ -n "$BL_DIR" ]; then
		MAX=$(chai_bl_max)
		RAW=$(((VAL * MAX + 127) / 255))
		# Don't let a small non-zero value round down to backlight off
		[ "$VAL" -gt 0 ] && [ "$RAW" -eq 0 ] && RAW=1
		echo "$RAW" >"$BL_DIR/brightness"
		[ -e "$BL_DIR/bl_power" ] && echo 0 >"$BL_DIR/bl_power"
	else
		echo setbl >/sys/kernel/debug/dispdbg/command
		echo lcd0 >/sys/kernel/debug/dispdbg/name
		echo "$VAL" >/sys/kernel/debug/dispdbg/param
		echo 1 >/sys/kernel/debug/dispdbg/start
	fi
}

# ---------------------------------------------------------------------------
# Battery: kernel power_supply
# ---------------------------------------------------------------------------

chai_battery_dir() {
	for D in \
		/sys/class/power_supply/cw221X-bat \
		/sys/class/power_supply/axp2202-battery \
		/sys/class/power_supply/battery; do
		[ -d "$D" ] && { echo "$D"; return 0; }
	done
	for D in /sys/class/power_supply/*; do
		[ "$(cat "$D/type" 2>/dev/null)" = "Battery" ] && { echo "$D"; return 0; }
	done
	return 1
}

# Prints $1 if it's a 0-100 integer (clamped), fails otherwise
chai_print_percent() {
	case "$1" in '' | *[!0-9]*) return 1 ;; esac
	[ "$1" -gt 100 ] && echo 100 || echo "$1"
}

# Kernel status string to 1 (Charging) or 0 (anything else, including Full)
chai_print_charging() {
	[ "$1" = "Charging" ] && echo 1 || echo 0
}

chai_default_get_battery_percent() {
	D=$(chai_battery_dir) || return 1
	chai_print_percent "$(tr -d '[:space:]' <"$D/capacity" 2>/dev/null)"
}

chai_default_get_battery_status() {
	D=$(chai_battery_dir)
	chai_print_charging "$(head -n 1 "$D/status" 2>/dev/null | tr -d '\r')"
}

# ---------------------------------------------------------------------------
# Idle suppression: hide the clamshell lid sensor
# ---------------------------------------------------------------------------
# Bind-mounts a "1" (lid open) over the hall sensor so the CFW doesn't sleep
# when the lid closes. A bind mount is gone after a reboot, so a crash can't
# leave it. Profiles that need saved state should use chai_idle_mark/unmark
# so a second "1" doesn't save the suppressed values as the user's.

CHAI_HALL_SENSORS="/sys/class/power_supply/axp2202-battery/hallkey /sys/devices/platform/hall-mh248/hallvalue"

chai_lid_hide() {
	for T in $CHAI_HALL_SENSORS; do
		[ -e "$T" ] || continue
		mountpoint -q "$T" && continue
		mount --bind "$CHAI_RETRO_DIR/default/hallkey" "$T"
	done
}

chai_lid_restore() {
	for T in $CHAI_HALL_SENSORS; do
		[ -e "$T" ] || continue
		# Lazy unmount for busy sysfs, looped in case of stacked mounts
		while mountpoint -q "$T"; do
			umount -l "$T" 2>/dev/null || break
		done
	done
}

# Returns 1 if suppression was already on (so callers skip saving state)
chai_idle_mark() {
	mkdir -p "$CHAI_RUN_DIR"
	[ -e "$CHAI_RUN_DIR/idle_suppressed" ] && return 1
	: >"$CHAI_RUN_DIR/idle_suppressed"
}

# Returns 1 if suppression was already off
chai_idle_unmark() {
	[ -e "$CHAI_RUN_DIR/idle_suppressed" ] || return 1
	rm -f "$CHAI_RUN_DIR/idle_suppressed"
}

chai_default_set_idle_suppression() {
	case "$1" in
		1) chai_idle_mark && chai_lid_hide ;;
		0) chai_idle_unmark && chai_lid_restore ;;
	esac
	return 0
}

# ---------------------------------------------------------------------------
# Volume subscribers
# ---------------------------------------------------------------------------
# Subscribers run as: <path> VOLUME MAX
# Whatever setup.sh installed to watch the volume (a wrapper, a listener)
# calls "chai notify-volume VOLUME MAX", which fans out to every subscriber.

chai_abs_path() {
	echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

chai_add_volume_subscriber() {
	SUB=$(chai_abs_path "$1")
	mkdir -p "$CHAI_RUN_DIR"
	touch "$CHAI_VOL_SUBS"
	grep -qxF "$SUB" "$CHAI_VOL_SUBS" || echo "$SUB" >>"$CHAI_VOL_SUBS"
}

chai_remove_volume_subscriber() {
	SUB=$(chai_abs_path "$1")
	[ -f "$CHAI_VOL_SUBS" ] || return 0
	grep -vxF "$SUB" "$CHAI_VOL_SUBS" >"$CHAI_VOL_SUBS.tmp"
	mv -f "$CHAI_VOL_SUBS.tmp" "$CHAI_VOL_SUBS"
}

chai_notify_volume() {
	[ -s "$CHAI_VOL_SUBS" ] || return 0
	while IFS= read -r SUB; do
		[ -x "$SUB" ] && "$SUB" "$1" "${2:-100}" </dev/null >/dev/null 2>&1 &
	done <"$CHAI_VOL_SUBS"
}

# ---------------------------------------------------------------------------
# Paths: unknown on an unknown CFW
# ---------------------------------------------------------------------------

chai_default_get_path() {
	return 1
}

# ---------------------------------------------------------------------------
# Public names. Profiles override these, and can still call chai_default_*
# to fall back.
# ---------------------------------------------------------------------------

chai_get_brightness() { chai_default_get_brightness "$@"; }
chai_set_brightness() { chai_default_set_brightness "$@"; }
chai_get_battery_percent() { chai_default_get_battery_percent "$@"; }
chai_get_battery_status() { chai_default_get_battery_status "$@"; }
chai_set_idle_suppression() { chai_default_set_idle_suppression "$@"; }
chai_get_path() { chai_default_get_path "$@"; }

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

chai_usage() {
	cat >&2 <<EOF
usage: chai <command> [args]

commands:
  get-brightness
  set-brightness N               (N = 0-255)
  get-battery-percent
  get-battery-status
  set-idle-suppression N         (N = 0 or 1)
  add-volume-subscriber path
  remove-volume-subscriber path
  get-path name                  (userdata, screenshots, media, roms)
EOF
}

chai_main() {
	cmd=$1
	[ $# -gt 0 ] && shift
	case $cmd in
		get-brightness) chai_get_brightness ;;
		set-brightness) chai_set_brightness "$@" ;;
		get-battery-percent) chai_get_battery_percent ;;
		get-battery-status) chai_get_battery_status ;;
		set-idle-suppression) chai_set_idle_suppression "$@" ;;
		add-volume-subscriber) chai_add_volume_subscriber "$@" ;;
		remove-volume-subscriber) chai_remove_volume_subscriber "$@" ;;
		get-path) chai_get_path "$@" ;;
		notify-volume) chai_notify_volume "$@" ;;
		*)
			chai_usage
			exit 1
			;;
	esac
}

[ -n "$CHAI_PROFILE_SOURCED" ] || chai_main "$@"
