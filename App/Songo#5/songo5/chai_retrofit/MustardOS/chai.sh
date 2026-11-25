#!/bin/sh
# CHAI retrofit: muOS
#
# Andromeda (2606) onwards and older releases. Anything not overridden here
# uses the default profile.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/chai.sh"

# Version is YYMM.N_CODENAME, Andromeda is 2606. Missing or unreadable means
# a release older than the version file.
MUOS_VERSION=$(cat /opt/muos/config/system/version 2>/dev/null)
MUOS_VERSION_MAJOR=${MUOS_VERSION%%.*}
case "$MUOS_VERSION_MAJOR" in
	'' | *[!0-9]*) MUOS_ANDROMEDA=0 ;;
	*) [ "$MUOS_VERSION_MAJOR" -ge 2606 ] && MUOS_ANDROMEDA=1 || MUOS_ANDROMEDA=0 ;;
esac

# Reads the hardware value, not muOS's saved setting, because set-brightness
# (default profile) writes the hardware directly during fades.
chai_get_brightness() {
	(
		. /opt/muos/script/var/func.sh
		RAW=$(DISPLAY_READ lcd0 getbl)
		case "$RAW" in '' | *[!0-9]*) exit 1 ;; esac

		# Andromeda's DISPLAY_READ returns the raw sysfs value when a backlight
		# device exists. DISPLAY_SYSFS_BACKLIGHT sets BL_PATH_CACHE rather than
		# printing it. Older releases only read dispdbg, which is already 0-255.
		if [ "$MUOS_ANDROMEDA" = 1 ] && DISPLAY_SYSFS_BACKLIGHT; then
			MAX=$(cat "$BL_PATH_CACHE/max_brightness" 2>/dev/null)
			case "$MAX" in '' | *[!0-9]* | 0) MAX=255 ;; esac
			RAW=$(((RAW * 255 + MAX / 2) / MAX))
			[ "$RAW" -gt 255 ] && RAW=255
		fi
		echo "$RAW"
	)
}

# mubattery writes its calibrated capacity here, the value muOS's UI shows
chai_get_battery_percent() {
	chai_print_percent "$(tr -d '[:space:]' </run/muos/battery/capacity 2>/dev/null)" && return 0

	# Daemon not running, read the device's configured capacity file
	CAP_PATH=$(head -n 1 /opt/muos/device/config/battery/capacity 2>/dev/null)
	[ -n "$CAP_PATH" ] && chai_print_percent "$(tr -d '[:space:]' <"$CAP_PATH" 2>/dev/null)" && return 0

	chai_default_get_battery_percent
}

chai_get_battery_status() {
	# Kernel status for the battery muOS is configured to use
	CAP_PATH=$(head -n 1 /opt/muos/device/config/battery/capacity 2>/dev/null)
	if [ -n "$CAP_PATH" ]; then
		STATUS=$(head -n 1 "$(dirname "$CAP_PATH")/status" 2>/dev/null | tr -d '\r')
		[ -n "$STATUS" ] && { chai_print_charging "$STATUS"; return 0; }
	fi

	# muOS's own flag means "charger plugged in", so it stays 1 when full
	CHG=$(tr -d '[:space:]' </run/muos/battery/charging 2>/dev/null)
	case "$CHG" in
		1 | 0) echo "$CHG"; return 0 ;;
	esac

	chai_default_get_battery_status
}

# Zeroes muOS's idle timers (saving the user's values to restore later).
# Andromeda also sets its CAFFEINE flag, which hotkey.sh's SLEEP() checks, so
# lid close and idle sleep are skipped. Older releases have no CAFFEINE, so
# the lid sensor is hidden instead (lid.sh polls the hallkey).
chai_set_idle_suppression() {
	ORIG="$CHAI_RUN_DIR/muos_idle_orig"
	case "$1" in
		1)
			chai_idle_mark || return 0
			(
				. /opt/muos/script/var/func.sh
				printf '%s %s\n' "$(GET_VAR config settings/power/idle_sleep)" \
					"$(GET_VAR config settings/power/idle_display)" >"$ORIG"
				[ "$MUOS_ANDROMEDA" = 1 ] && CAFFEINE on
				SET_VAR config settings/power/idle_sleep 0
				SET_VAR config settings/power/idle_display 0
				HOTKEY restart
			)
			[ "$MUOS_ANDROMEDA" = 1 ] || chai_lid_hide
			;;
		0)
			chai_idle_unmark || return 0
			(
				. /opt/muos/script/var/func.sh
				read -r IDLE_SLEEP IDLE_DISPLAY <"$ORIG"
				[ "$MUOS_ANDROMEDA" = 1 ] && CAFFEINE off
				SET_VAR config settings/power/idle_sleep "$IDLE_SLEEP"
				SET_VAR config settings/power/idle_display "$IDLE_DISPLAY"
				HOTKEY restart
			)
			rm -f "$ORIG"
			[ "$MUOS_ANDROMEDA" = 1 ] || chai_lid_restore
			;;
	esac
	return 0
}

# muOS bind-mounts each location to whichever SD card holds it under
# /run/muos/storage
chai_get_path() {
	STORE=/run/muos/storage
	case "$1" in
		userdata) echo "$STORE" ;;
		screenshots) echo "$STORE/screenshot" ;;
		media) echo "$STORE/music" ;;
		roms) echo "$(cat /opt/muos/device/config/storage/rom/mount 2>/dev/null || echo /mnt/mmc)/ROMS" ;;
		*) return 1 ;;
	esac
}

chai_main "$@"
