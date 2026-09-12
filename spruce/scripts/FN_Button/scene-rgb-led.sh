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

# defaultLEDcolor is a name in config; led_color_hex (trimui_delegate.sh) maps it.
hex="$(led_color_hex)"

# Note: rgb_led_trimui "off" sets effect=0 (disable), which only FREEZES the
# animation engine -- the LEDs keep their last lit colour rather than going dark.
# To actually extinguish them we drive a static effect with colour 000000.
# The black write below only holds until something else writes a colour, and
# plenty does: principal.sh runs set_rgb_in_menu on every return to the menu, and
# led_effect re-colours on every game launch. So record the state in a flag that
# rgb_led_trimui honours, and the LEDs stay off until this action turns them back
# on. Order matters both ways - write while the flag is clear, or rgb_led_trimui
# early-outs on our own call.
case "$1" in
    1)  # switch on -> LEDs off (black)
        flag_remove "leds_forced_off"
        rgb_led_trimui lrm12 static "000000"
        flag_add "leds_forced_off" --tmp
        ;;
    0)  # switch off -> LEDs on (configured colour)
        flag_remove "leds_forced_off"
        rgb_led_trimui lrm12 static "$hex"
        ;;
esac
