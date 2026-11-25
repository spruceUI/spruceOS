#!/bin/sh
# CHAI retrofit: TrimUI stock firmware and CrossMix (Smart Pro, Brick)
#
# Both run TrimUI's closed source MainUI, so they share one profile. Anything
# not overridden here uses the default profile (axp2202-battery for the
# battery).

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/chai.sh"

# The panel is driven through /dev/disp. NextUI's helper does the same ioctl
# as TrimUI's own brightness code and reads back the real value (0 after a
# fade-out). It exits non-zero without /dev/disp, falling back to the default
# profile (sysfs backlight, then dispdbg, which CrossMix's lcd_off.sh uses).
TRIMUI_BACKLIGHT="$CHAI_RETRO_DIR/NextUI/backlight"

chai_get_brightness() {
	[ -e /dev/disp ] && "$TRIMUI_BACKLIGHT" get 2>/dev/null && return 0
	chai_default_get_brightness
}

chai_set_brightness() {
	case "$1" in '' | *[!0-9]*) return 1 ;; esac
	[ -e /dev/disp ] && "$TRIMUI_BACKLIGHT" set "$1" 2>/dev/null && return 0
	chai_default_set_brightness "$1"
}

# Idle suppression stays on the default profile. MainUI's idle and sleep
# handling is closed source and has no switch to turn it off from outside.
# Neither device has a lid, so the default profile's hallkey mount does nothing.

# TODO: confirm screenshots and media locations on TrimUI and CrossMix
chai_get_path() {
	case "$1" in
		userdata) echo /mnt/SDCARD ;;
		roms) echo /mnt/SDCARD/Roms ;;
		*) chai_default_get_path "$@" ;;
	esac
}

chai_main "$@"
