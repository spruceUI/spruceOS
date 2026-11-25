#!/bin/sh
# CHAI retrofit: Spruce
#
# Anything not overridden here uses the default profile.

CHAI_PROFILE_SOURCED=1
. "$(dirname "$0")/../default/chai.sh"

# Scales a raw backlight value to 0-255. $1 raw value, $2 panel max
chai_spruce_to_255() {
	MAX="$2"
	case "$MAX" in '' | *[!0-9]* | 0) MAX=255 ;; esac
	V=$((($1 * 255 + MAX / 2) / MAX))
	[ "$V" -gt 255 ] && V=255
	echo "$V"
}

# Allwinner devices (TrimUI Brick, Smart Pro, Anbernic H700) drive the panel
# through /dev/disp, as spruce's own set_backlight does. NextUI's helper does
# the same ioctl without spruce's python, fast enough for Songo's per-frame
# fades, and reads back the real value (0 after a fade-out). It exits non-zero
# without /dev/disp, falling through to the code below.
SPRUCE_DISP_BACKLIGHT="$CHAI_RETRO_DIR/NextUI/backlight"

chai_set_brightness() {
	case "$1" in '' | *[!0-9]*) return 1 ;; esac
	[ -e /dev/disp ] && "$SPRUCE_DISP_BACKLIGHT" set "$1" 2>/dev/null && return 0
	chai_default_set_brightness "$1"
}

chai_get_brightness() {
	[ -e /dev/disp ] && "$SPRUCE_DISP_BACKLIGHT" get 2>/dev/null && return 0

	# Spruce's device config points at the panel's sysfs brightness file
	if [ -n "$DEVICE_BRIGHTNESS_PATH" ] && [ -f "$DEVICE_BRIGHTNESS_PATH" ]; then
		RAW=$(cat "$DEVICE_BRIGHTNESS_PATH" 2>/dev/null)
		MAX=$(cat "$(dirname "$DEVICE_BRIGHTNESS_PATH")/max_brightness" 2>/dev/null)
		case "$RAW" in
			'' | *[!0-9]*) ;;
			*) chai_spruce_to_255 "$RAW" "$MAX" && return 0 ;;
		esac
	fi

	. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

	# Spruce stores brightness as a 0-10 step
	STEP=$(current_backlight)
	case "$STEP" in '' | *[!0-9]*) return 1 ;; esac
	[ "$STEP" -gt 10 ] && return 1

	# Devices that define SYSTEM_BRIGHTNESS_<step> map each step to a raw
	# backlight value
	if [ -n "${SYSTEM_BRIGHTNESS_0+x}" ]; then
		eval "RAW=\${SYSTEM_BRIGHTNESS_$STEP}"
		case "$RAW" in '' | *[!0-9]*) return 1 ;; esac
		chai_bl_detect && [ -n "$BL_DIR" ] && MAX=$(chai_bl_max) || MAX=255
		chai_spruce_to_255 "$RAW" "$MAX"
		return 0
	fi

	# Brick and Smart Pro
	[ "$STEP" -lt 2 ] && echo 4 || echo $(((STEP - 1) * 254 / 9 + 1))
}

# TODO: confirm screenshots and media locations on Spruce
chai_get_path() {
	case "$1" in
		userdata) echo /mnt/SDCARD ;;
		roms) echo /mnt/SDCARD/Roms ;;
		*) chai_default_get_path "$@" ;;
	esac
}

chai_main "$@"
