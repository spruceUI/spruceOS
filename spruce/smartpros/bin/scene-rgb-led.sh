#!/bin/sh
# Switch scene action: toggle the RGB LEDs through spruce's own LED system.
#
# trimui_scened runs this with arg 1 (switch on) / 0 (switch off). The stock
# com.trimui.ledc.sh cannot be used here: it derives brightness from the TrimUI
# shared-memory var (shmvar 10), which spruce never populates (spruce drives the
# LEDs via rgb_led / the RGB LED Settings instead), so on this device shmvar 10 is
# 0 and ledc.sh always resolves to max_scale 0 (LEDs dark) regardless of switch
# position. Going through rgb_led_trimui keeps the switch in sync with spruce's
# own LED state, the LEDmaxScale brightness, and the disableLEDs setting.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_delegate.sh

# defaultLEDcolor is a name in config; map the common ones to hex, default white.
case "$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDcolor.selected' "White")" in
    Red)     hex="FF0000" ;;
    Green)   hex="00FF00" ;;
    Blue)    hex="0000FF" ;;
    Yellow)  hex="FFFF00" ;;
    Cyan)    hex="00FFFF" ;;
    Magenta) hex="FF00FF" ;;
    Orange)  hex="FF8800" ;;
    *)       hex="FFFFFF" ;;
esac

# Note: rgb_led_trimui "off" sets effect=0 (disable), which only FREEZES the
# animation engine -- the LEDs keep their last lit colour rather than going dark.
# To actually extinguish them we drive a static effect with colour 000000.
case "$1" in
    1)  rgb_led_trimui lrm12 static "000000" ;;  # switch on  -> LEDs off (black)
    0)  rgb_led_trimui lrm12 static "$hex" ;;    # switch off -> LEDs on (colour)
esac
