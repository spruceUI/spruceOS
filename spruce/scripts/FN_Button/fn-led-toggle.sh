#!/bin/sh
# Toggle the RGB LEDs on/off from the Fn key, in sync with spruce's own RGB
# state. The stock script wrote /tmp/system/enable_led, which the stock firmware
# daemons consumed; spruce does not, and it drives the LEDs itself through
# /sys/class/led_anim (see enable_or_disable_rgb_trimui / set_rgb_in_menu). So
# the stock toggle could switch the LEDs off but never restore them, because
# nothing re-applied spruce's configured colour/effect.
#
# Here we use spruce's own primitives: the led_anim "enable" gate is the on/off
# state, and turning back on re-applies the user's configured colour/effect via
# set_rgb_in_menu so the LEDs return to exactly what spruce would show.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

ENABLE_FILE="/sys/class/led_anim/enable"

CURRENT=$(cat "$ENABLE_FILE" 2>/dev/null)
echo "get led enable:$CURRENT"

if [ "$CURRENT" = "1" ]; then
    echo "set LED off"
    chmod 777 "$ENABLE_FILE" 2>/dev/null
    echo 0 > "$ENABLE_FILE" 2>/dev/null
else
    echo "set LED on"
    chmod 777 "$ENABLE_FILE" 2>/dev/null
    echo 1 > "$ENABLE_FILE" 2>/dev/null
    # Restore spruce's configured colour/effect so "on" matches the menu state.
    set_rgb_in_menu
fi
