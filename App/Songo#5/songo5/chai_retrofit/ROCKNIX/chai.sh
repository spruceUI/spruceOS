#!/bin/sh
# CHAI retrofit: ROCKNIX
#
# Anything not overridden here uses the default profile.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/chai.sh"

# ROCKNIX's saved brightness setting is a percent
chai_get_brightness() {
	PCT=$(. /etc/profile.d/001-functions && get_setting display.brightness)
	case "$PCT" in '' | *[!0-9]*) return 1 ;; esac
	echo $(((PCT * 255) / 100))
}

# batteryplus writes a voltage based percentage here, the same value ES shows
chai_get_battery_percent() {
	chai_print_percent "$(tr -d '[:space:]' </tmp/battery.percent 2>/dev/null)" && return 0
	for D in /sys/class/power_supply/[Bb][Aa][Tt]*; do
		[ -d "$D" ] || continue
		chai_print_percent "$(tr -d '[:space:]' <"$D/capacity" 2>/dev/null)" && return 0
	done
	chai_default_get_battery_percent
}

# Same battery rocknix-info reports
chai_get_battery_status() {
	for D in /sys/class/power_supply/[Bb][Aa][Tt]*; do
		[ -d "$D" ] || continue
		STATUS=$(head -n 1 "$D/status" 2>/dev/null | tr -d '\r')
		[ -n "$STATUS" ] && { chai_print_charging "$STATUS"; return 0; }
	done
	chai_default_get_battery_status
}

# The lid is an SW_LID input event, not a sysfs file, so the default hallkey
# bind mount does nothing here. Two things can act on it:
#  - systemd-logind (HandleLidSwitch=suspend) when a suspend mode is set.
#    Holding a handle-lid-switch lock makes logind ignore the lid. The lock
#    goes away with the process, so a crash can't leave it.
#  - rocknix-fake-suspend when suspend mode is off. It reads
#    system.suspend.enable on every lid event, so it applies straight away.
# TODO: idle sleep isn't covered yet, same as the old playback_suppressions.
ROCKNIX_INHIBIT_PID="$CHAI_RUN_DIR/rocknix-lid-inhibit.pid"
ROCKNIX_FAKE_SUSPEND_ORIG="$CHAI_RUN_DIR/rocknix-fake-suspend.orig"

chai_set_idle_suppression() {
	case "$1" in
		1)
			chai_idle_mark || return 0
			systemd-inhibit --what=handle-lid-switch --who=CHAI --why="Idle suppression" \
				--mode=block sleep infinity >/dev/null 2>&1 &
			echo $! >"$ROCKNIX_INHIBIT_PID"
			(
				. /etc/profile.d/001-functions
				# Empty when never set, which rocknix-fake-suspend treats as enabled
				get_setting system.suspend.enable >"$ROCKNIX_FAKE_SUSPEND_ORIG"
				[ "$(get_setting system.suspendmode)" = "off" ] && set_setting system.suspend.enable 0
			)
			;;
		0)
			chai_idle_unmark || return 0
			[ -f "$ROCKNIX_INHIBIT_PID" ] && kill "$(cat "$ROCKNIX_INHIBIT_PID")" 2>/dev/null
			rm -f "$ROCKNIX_INHIBIT_PID"
			(
				. /etc/profile.d/001-functions
				# "default" deletes the setting, restoring it to unset
				ORIG=$(cat "$ROCKNIX_FAKE_SUSPEND_ORIG" 2>/dev/null)
				set_setting system.suspend.enable "${ORIG:-default}"
			)
			rm -f "$ROCKNIX_FAKE_SUSPEND_ORIG"
			;;
	esac
	return 0
}

# TODO: confirm screenshots and media locations on ROCKNIX
chai_get_path() {
	case "$1" in
		userdata) echo /storage ;;
		roms) echo /storage/roms ;;
		*) chai_default_get_path "$@" ;;
	esac
}

chai_main "$@"
