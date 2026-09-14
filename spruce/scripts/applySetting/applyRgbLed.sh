#!/bin/sh
# Apply RGB LED settings dynamically when changed in PyUI configuration menu.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/platform/device.sh
[ -f /mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh ] && . /mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh

# 1. Check if LEDs are disabled
disable_leds="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
if [ "$disable_leds" = "True" ]; then
    echo 0 > /sys/class/led_anim/max_scale 2>/dev/null
    rgb_led "lrm12" "static" "000000"
    flag_add "leds_forced_off" --tmp
    exit 0
fi

# 2. Update peak brightness
brightness="$(get_config_value '.menuOptions."RGB LED Settings".LEDmaxScale.selected' "25")"
case "$brightness" in
    ''|*[!0-9]*) brightness=25 ;;
esac
chmod -R 777 /sys/class/led_anim 2>/dev/null
echo "$brightness" > /sys/class/led_anim/max_scale 2>/dev/null
echo 1 > /sys/class/led_anim/enable 2>/dev/null
echo 1 > /sys/class/led_anim/effect_enable 2>/dev/null

flag_remove "leds_forced_off"

# 3. Apply LED behavior and color
case "$1" in
    "preview_emu"|*"emu"*)
        color_name="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDcolor.selected' "Cyan")"
        [ "$color_name" = "System-specific" ] && color_name="Cyan"
        effect="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDeffect.selected' "static")"
        duration="$(get_config_value '.menuOptions."RGB LED Settings".emuLEDduration.selected' "1000")"
        color_hex="$(map_color_name_to_hex "$color_name")"
        rgb_led "lrm12" "$effect" "$color_hex" "$duration" "-1"
        ;;
    *)
        set_rgb_in_menu
        ;;
esac
