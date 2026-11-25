#!/bin/sh
# CHAI retrofit: NextUI
#
# PortMaster runs as a NextUI pak, so this inherits NextUI's pak environment
# (SDCARD_PATH, ROMS_PATH, USERDATA_PATH, PLATFORM, DEVICE...) from
# MinUI.pak/launch.sh. Anything not overridden here uses the default profile.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/chai.sh"

NEXTUI_BACKLIGHT="$CHAI_RETRO_DIR/NextUI/backlight"

# tg5040 and h700 drive the backlight through /dev/disp, the same as
# libmsettings. tg5050 has no /dev/disp (backlight exits 2) and uses sysfs
# backlight0, which the default profile covers.
chai_get_brightness() {
	"$NEXTUI_BACKLIGHT" get 2>/dev/null || chai_default_get_brightness
}

chai_set_brightness() {
	case "$1" in '' | *[!0-9]*) return 1 ;; esac
	"$NEXTUI_BACKLIGHT" set "$1" 2>/dev/null || chai_default_set_brightness "$1"
}

# NextUI's batmon daemon writes the percentage NextUI shows here
chai_get_battery_percent() {
	chai_print_percent "$(tr -d '[:space:]' </tmp/percBat 2>/dev/null)" && return 0
	chai_default_get_battery_percent
}

# Idle suppression stays on the default profile. While a PortMaster app runs,
# nothing in NextUI sleeps the device: idle and lid sleep live in its in-app
# PWR_update, not in keymon. If the app leaves something running in the
# background and exits, NextUI's menu is back, and on h700 clamshells it reads
# the lid from axp2202-battery/hallkey, which the default profile hides.
# NextUI's menu autosleep can't be blocked from outside.

# NextUI has no screenshots or music folder
chai_get_path() {
	case "$1" in
		userdata) echo "${USERDATA_PATH:-/mnt/SDCARD/.userdata/$PLATFORM}" ;;
		roms) echo "${ROMS_PATH:-/mnt/SDCARD/Roms}" ;;
		*) chai_default_get_path "$@" ;;
	esac
}

chai_main "$@"
