#!/bin/sh

# Requires:
#   PLATFORM
#   EMU_JSON_PATH
#   get_config_value
#   jq
#   rgb_led
#   sleep
#
# Provides:
#   led_effect

led_effect() {
	use_effect="$(get_config_value '.menuOptions."RGB LED Settings".emulatorLEDeffect.selected' "True")"
	if [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "Flip" ] || [ "$use_effect" = "False" ]; then
		return 0	# exit if device has no LEDs to twinkle or user opts out
	fi
	COLOR="$(jq -r '.themecolor' "$EMU_JSON_PATH")"
	if [ -z "$COLOR" ] || [ "$COLOR" = "null" ]; then
		COLOR="FFFFFF"
	fi
	rgb_led lrm12 breathe "$COLOR" 1200 3
	sleep 5
	rgb_led lrm12 breathe "$COLOR" 4000 -1
}