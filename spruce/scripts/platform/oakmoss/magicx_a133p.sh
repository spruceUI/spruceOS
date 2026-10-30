#!/bin/sh

# The MagicX boards (Mini Zero 28, Zero 40, XU20 V32) on oakMOSS: the oakMOSS A133P base. Their own
# differences live in Zero28.sh, Zero40.sh, XU20.sh and their platform cfgs.

. "/mnt/SDCARD/spruce/scripts/platform/oakmoss/oakmoss_a133p.sh"

# The work LED is a MagicX pin, written through the whole PB data register (utils/magicx/led.sh), so only
# this tier has it: the other oakMOSS boards keep common64bit.sh's stubs and never touch port B.
work_led_off() {
    /mnt/SDCARD/spruce/scripts/platform/utils/magicx/led.sh off
}

work_led_on() {
    /mnt/SDCARD/spruce/scripts/platform/utils/magicx/led.sh on
}
