#!/bin/sh

# Requires:
#   PLATFORM
#   EMU_JSON_PATH
#   get_config_value()
#   jq
#   rgb_led()
#   map_color_name_to_hex()
#
# Provides:
#   led_effect

led_effect() {
	# opt in or out of emulator-specific LED settings
	use_effect="$(get_config_value '.menuOptions."RGB LED Settings".enableEmuSpecificLEDbehavior.selected' "True")"
	if [ "$use_effect" = "False" ]; then
		return 0	# exit if device has no LEDs to twinkle or user opts out
	fi

	# get system-specific color from emu config.json
	THEME_COLOR="$(jq -r '.themecolor' "$EMU_JSON_PATH")"
	if [ -z "$THEME_COLOR" ] || [ "$THEME_COLOR" = "null" ]; then
		THEME_COLOR="FFFFFF"
	fi

	color_name="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDcolor.selected' "System-specific")"
    effect="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDeffect.selected' "breathe")"
    duration="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDduration.selected' "4000")"

	if [ "$color_name" = "System-specific" ]; then
		color_hex="$THEME_COLOR"
	else
		color_hex="$(map_color_name_to_hex "$color_name")"
	fi

	rgb_led lrm12 "$effect" "$color_hex" "$duration" "-1"
}